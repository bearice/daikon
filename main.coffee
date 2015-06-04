fs = require 'fs'
dns = require 'dns'
util = require 'util'
https = require 'https'
URL = require 'url'
EventEmitter = (require 'events').EventEmitter

_ = require 'underscore'
Etcd = require 'node-etcd-promise'
Docker = require 'dockerode-promise'
Promise = require 'promise'
JSONStream = require 'JSONStream'

DockerStatsStream = require './dockerstats'

HOST_NAME = process.env.HOST_NAME
HOST_ADDR = process.env.HOST_ADDR

perror = (e)->
  console.error e
  console.error e.stack

pass = -> Promise.resolve 'pass'

class Monitor
  constructor: (@container)->
    @container.inspect().then(@onStart).done()

  onData: (data) =>
    #console.info @info.Name, data.cpu_stats.percent.total
    #TODO write stats data into kafka

  onStart: (@info)=>
    console.info "Start #{@info.Id}#{@info.Name}"
    @info.Name = @info.Name.replace(/^\//,'')
    @_env = @getEnv()
    @_ports = @getPorts()
    @stream = new DockerStatsStream @container
    @stream.on 'data', @onData
    @checkApp()
    @updateEtcd()

  onDeath: =>
    console.info "Stop #{@info.Id}"
    @stream.removeListener 'data', @onData
    clearTimeout @_timer if @_timer
    @cleanEtcd()

  checkApp: =>
    if @_env.APP_CHECK
      @container.exec
        Cmd: @_env.APP_CHECK.split(' ')
        AttachStdout: true
        AttachStderr: true
      .then (exec)=>
        Promise.denodeify(exec.start).call(exec)
        .then (resp)=>
          new Promise (accept,reject) ->
            buf = []
            resp.setEncoding 'utf-8'
            resp
              .on 'data', (data) ->
                buf.push data
              .on 'end', ->
                console.info buf.join("")
                accept exec
              .on 'error', reject
        .then (exec) ->
          Promise.denodeify(exec.inspect).call(exec)
      .then (info) =>
        console.info info
        @registerApp()
      .catch perror
    else
      @registerApp()

  registerApp: =>
    if @_env.APP_NAME and @_env.ENV_NAME
      etcd.set("/docker/apps/#{@_env.ENV_NAME}/#{@_env.APP_NAME}/#{@info.Name}@#{HOST_NAME}", @info.Id, {ttl: 60})
    else
      pass()

  cleanApp: =>
    if @_env.APP_NAME and @_env.ENV_NAME
      etcd.del("/docker/apps/#{@_env.ENV_NAME}/#{@_env.APP_NAME}/#{@info.Name}@#{HOST_NAME}")
    else
      pass()

  registerInstance: =>
    path = "/docker/instances/#{@info.Id}"
    etcd.mkdir(path, {ttl: 60, prevExist: false}).then =>
      Promise.all [
        etcd.set("#{path}/raw",   JSON.stringify(@info)),
        etcd.set("#{path}/host",  HOST_NAME),
        etcd.set("#{path}/ports", JSON.stringify(@_ports)),
      ]
    .catch =>
      etcd.mkdir(path, {ttl: 60, prevExist: true})

  cleanInstance: =>
    etcd.rmdir("/docker/instances/#{@info.Id}", {recursive: true})

  updateEtcd: =>
    console.info "Update #{@info.Id}"
    @_timer = setTimeout @updateEtcd, 30*1000
    @registerInstance().then @checkApp

  cleanEtcd: =>
    console.info "Remove #{@info.Id}"
    @cleanApp().then @cleanInstance

  getEnv: =>
    @info.Config.Env.reduce (acc,str)->
      i = str.indexOf '='
      return acc unless i>0
      k = str.substr 0,i
      v = str.substr i+1
      acc[k] = v
      return acc
    ,{}

  getPorts: =>
    ret = {}
    for k,v of @info.NetworkSettings.Ports
      ret[k] = "#{HOST_ADDR}:#{v[0].HostPort}" if v
    return ret

class Reactor
  constructor: (@docker)->
    @monitors = {}
    @docker.getEvents()
      .then (stream)=>
        @stream = stream.pipe(JSONStream.parse())
        @stream.on 'data', @onEvent
      .done()

  addMonitor: (id) =>
    console.info "Add #{id}"
    @monitors[id] = new Monitor @docker.getContainer id

  delMonitor: (id) =>
    console.info "Del #{id}"
    @monitors[id].onDeath()
    delete @monitors[id]

  onEvent: (event) =>
    switch event.status
      when 'start'
        @addMonitor event.id
      when 'die'
        @delMonitor event.id

  shutdown: =>
    if @_isShutdown
      console.info "Shutdown in process, force exit"
      process.exit(1)
    @_isShutdown = true
    console.info "Shuting down ..."
    Promise.all(_.map(@monitors, (m)->
      m.onDeath()
    )).then( ->
      console.info "Done cleanning up, bye~"
      process.exit(0)
    )

etcd = null
docker = null
reactor = null

resolveSrv = Promise.denodeify(dns.resolveSrv)
resolveSrv(process.env.ETCD_DNS_NAME || "_etcd._tcp.local")
.then (rr) ->
  console.info "etcd servers", rr
  rr.map (rr)->"#{rr.name}:#{rr.port}"
.then (etcdServers) ->
  etcdOpts =
    cert: fs.readFileSync process.env.ETCD_SSL_CERT || "etcd-client.crt"
    key:  fs.readFileSync process.env.ETCD_SSL_KEY  || "etcd-client.key"
    ca:  [fs.readFileSync process.env.ETCD_SSL_CA   || "ca.crt" ]

  etcd    = new Etcd etcdServers, etcdOpts
  docker  = new Docker socketPath: process.env.DOCKER_SOCK_PATH || '/var/run/docker.sock'
  reactor = new Reactor docker

  process.on 'SIGTERM', reactor.shutdown
  process.on 'SIGINT', reactor.shutdown

.then ->
  docker.listContainers()
.then (list) ->
  list.forEach (info) ->
    reactor.addMonitor info.Id
.catch perror


