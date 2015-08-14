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

resolveSrv = Promise.denodeify(dns.resolveSrv)
{execYields,getStreamContent} = require './promise-utils'

DockerStatsStream = require './dockerstats'

HOST_NAME = process.env.HOST_NAME
HOST_ADDR = process.env.HOST_ADDR

perror = (e)->
  console.error e
  console.error e.stack

pass = -> Promise.resolve 'pass'

class Monitor
  constructor: (@etcd,@container)->

  onStart: (@info)=>
    @info = yield @container.inspect()
    console.info "Start #{@info.Id}#{@info.Name}"
    @info.Name = @info.Name.replace(/^\//,'')
    @_env = @getEnv()
    @_ports = @getPorts()
    @updateEtcd()

  onDeath: =>
    console.info "Stop #{@info.Id}"
    @stream.removeListener 'data', @onData
    clearTimeout @_timer if @_timer
    @cleanEtcd()

  updateEtcd: =>
    console.info "Update #{@info.Id}"
    @_timer = setTimeout @updateEtcd, 1000*(20+Math.random()*20)
    execYields @registerInstance

  cleanEtcd: =>
    console.info "Remove #{@info.Id}"
    execYields @cleanInstance

  registerInstance: =>
    path = "/docker/instances/#{@info.Id}"
    yield @etcd.set("#{path}/raw",   JSON.stringify(@info),   ttl: 60),
    yield @etcd.set("#{path}/ports", JSON.stringify(@_ports), ttl: 60),
    yield @etcd.set("#{path}/host",  HOST_NAME,               ttl: 60),
    yield @etcd.set("#{path}/name",  @info.Name,              ttl: 60),
    yield @etcd.set("#{path}/ip",    @info.NetworkSettings.IPAddress, ttl: 60),
    yield @etcd.mkdir(path, {ttl: 60, prevExist: true})
    yield @checkApp()

  cleanInstance: =>
    yield etcd.rmdir("/docker/instances/#{@info.Id}", {recursive: true})

  checkApp: =>
    return if @_appCheckPassed
    if @_env.APP_CHECK
      exec = yield @container.exec
        Cmd: ["/bin/sh","-c", @_env.APP_CHECK]
        AttachStdout: true
        AttachStderr: true
      resp = yield exec.start()
      output = yield getStreamContent resp
      info = yield exec.inspect()
      console.info "#{@_env.APP_CHECK} => #{info.ExitCode}"
      yield etcd.set("/docker/instances/#{@info.Id}/app_check", info.ExitCode)
      yield etcd.set("/docker/instances/#{@info.Id}/app_check_msg", buf)
    else
      yield etcd.set("/docker/instances/#{@info.Id}/app_check", 0)
    @_appCheckPassed = true

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
    ip = HOST_ADDR
    for k,v of @info.NetworkSettings.Ports
      ret[k] = "#{ip}:#{v[0].HostPort}" if v
    return ret

class Reactor
  constructor: (@etcd,@docker)->
    @monitors = {}

  init: ->
    list = yield docker.listContainers()
    list.forEach (info) -> reactor.addMonitor info.Id
    @stream = yield @docker.getEvents()
    @stream = @stream.pipe(JSONStream.parse())
    @stream.on 'data', @onEvent
    process.on 'SIGTERM', @shutdown
    process.on 'SIGINT',  @shutdown

  addMonitor: (id) =>
    console.info "Add #{id}"
    @monitors[id] = new Monitor @etcd,@docker.getContainer id
    execYields @monitors[id].onStart

  delMonitor: (id) =>
    console.info "Del #{id}"
    @monitors[id]?.onDeath()
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

execYields ->
  rr = yield resolveSrv(process.env.ETCD_DNS_NAME || "_etcd._tcp.local")
  console.info "etcd servers", rr
  etcdServers = rr.map (rr)->"#{rr.name}:#{rr.port}"
  etcdOpts =
    cert: fs.readFileSync process.env.ETCD_SSL_CERT || "etcd-client.crt"
    key:  fs.readFileSync process.env.ETCD_SSL_KEY  || "etcd-client.key"
    ca:  [fs.readFileSync process.env.ETCD_SSL_CA   || "ca.crt" ]

  etcd    = new Etcd etcdServers, etcdOpts
  docker  = new Docker socketPath: process.env.DOCKER_SOCK_PATH || '/var/run/docker.sock'
  reactor = new Reactor etcd,docker
  yield reactor.init()



