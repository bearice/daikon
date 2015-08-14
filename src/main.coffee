fs = require 'fs'
os = require 'os'
ip = require 'ip'
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

argv = require 'minimisty'
if argv._flags.help || argv._flags.h
  console.info """
  Usage: daikon [options]
    -e --etcd      $ETCD_DNS_NAME  etcd dns name            [_etcd._tcp.local]
    -c --cert      $ETCD_SSL_CERT  etcd certificate         [certs/etcd-client.crt]
    -k --key       $ETCD_SSL_KEY   etcd key                 [certs/etcd-client.key]
    -a --ca        $ETCD_SSL_CA    etcd ca                  [certs/ca.crt]
    -n --nossl     $ETCD_NO_SSL    disable ssl
    -H --hostname  $HOSTNAME       report host name         [os.hostname()]
    -A --hostaddr  $HOSTADDR       report host ip           [auto detect]
    -I --hostintf  $HOSTINTF       report interface ip
    -d --docker    $DOCKER_SOCKET  docker socket path       [/var/run/docker.sock]
    -h --help                      show this message
  """
  process.exit(0)

HOSTNAME = process.env.HOSTNAME || argv['hostname'] || argv.H || os.hostname()
HOSTINTF = process.env.HOSTINTF || argv['hostintf'] || argv.I
HOSTADDR = process.env.HOSTADDR || argv['hostaddr'] || argv.A || ip.address HOSTINTF
DOCKER_SOCKET = process.env.DOCKER_SOCKET || argv['docker']   || argv.d || "/var/run/docker.sock"
ETCD_DNS_NAME = process.env.ETCD_DNS_NAME || argv['etcd']     || argv.e || "_etcd._tcp.local"
ETCD_SSL_CERT = process.env.ETCD_SSL_CERT || argv['cert']     || argv.c || "certs/etcd-client.crt"
ETCD_SSL_KEY  = process.env.ETCD_SSL_KEY  || argv['key']      || argv.k || "certs/etcd-client.key"
ETCD_SSL_CA   = process.env.ETCD_SSL_CA   || argv['ca']       || argv.a || "certs/ca.crt"
ETCD_SSL_ENABLE = !(argv._flags.nossl || argv._flags.n || process.env.ETCD_NO_SSL)

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
    yield @etcd.set("#{path}/host",  HOSTNAME,                ttl: 60),
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
    for k,v of @info.NetworkSettings.Ports
      ret[k] = "#{HOSTADDR}:#{v[0].HostPort}" if v
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

#main function
execYields ->
  rr = yield resolveSrv(ETCD_DNS_NAME)
  console.info "etcd servers", rr
  etcdServers = rr.map (rr)->"#{rr.name}:#{rr.port}"
  etcdOpts = if ETCD_SSL_ENABLE
    cert: fs.readFileSync ETCD_SSL_CERT
    key:  fs.readFileSync ETCD_SSL_KEY
    ca:  [fs.readFileSync ETCD_SSL_CA  ]
  etcd    = new Etcd etcdServers, etcdOpts
  docker  = new Docker socketPath: DOCKER_SOCKET
  reactor = new Reactor etcd,docker
  yield reactor.init()



