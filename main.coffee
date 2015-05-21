fs = require 'fs'
dns = require 'dns'
util = require 'util'
https = require 'https'
URL = require 'url'
EventEmitter = (require 'events').EventEmitter
Transform = require('stream').Transform
JSONStream = require 'JSONStream'

_ = require 'underscore'
Promise = require 'promise'
Docker = require 'dockerode'
Etcd = require 'node-etcd'
parseArgs = require 'minimist'

fiber = (fn)->
  (fibrous fn)((err,ret) ->
    throw err if err
    return ret
  )

class StatisticsStream
  util.inherits(StatisticsStream, Transform)
  constructor: (@container)->
    Transform.call(this, {readableObjectMode:true, objectMode:true})
    @last = null
    Promise.denodeify(@container.stats)
      .call(@container)
      .then (stream)=>
        stream.pipe(JSONStream.parse()).pipe(this)

  _transform: (obj,encoding,cb)->
    if @last
      obj.cpu_stats.percent = @calcCpuUsage obj
      @push obj

    @last = obj
    cb()

  calcCpuUsage: (obj)->
    cpu_cnt = obj.cpu_stats.cpu_usage.percpu_usage.length
    delta =
      clock: obj.cpu_stats.system_cpu_usage      - @last.cpu_stats.system_cpu_usage
      total: obj.cpu_stats.cpu_usage.total_usage - @last.cpu_stats.cpu_usage.total_usage
      umode: obj.cpu_stats.cpu_usage.usage_in_usermode   - @last.cpu_stats.cpu_usage.usage_in_usermode
      kmode: obj.cpu_stats.cpu_usage.usage_in_kernelmode - @last.cpu_stats.cpu_usage.usage_in_kernelmode

    percent =
      total: delta.total / delta.clock * cpu_cnt * 100
      umode: delta.umode / delta.clock * cpu_cnt * 100
      kmode: delta.kmode / delta.clock * cpu_cnt * 100

    return percent

class Monitor
  constructor: (@container)->
    Promise.denodeify(@container.inspect)
      .call(@container)
      .then (@info)=>
        @stream = new StatisticsStream @container
        @stream.on 'data', @onData

  onData: (data) =>
    console.info @info.Name, data.cpu_stats.percent.total

  stop: =>
    @stream.removeListener 'data', @onData

class Reactor
  constructor: (@docker)->
    @monitors = {}
    Promise.denodeify(@docker.getEvents)
      .call(@docker)
      .then (stream)=>
        @stream = stream.pipe(JSONStream.parse())
        @stream.on 'data', @onEvent

  addMonitor: (id) =>
    console.info "Add #{id}"
    @monitors[id] = new Monitor @docker.getContainer id

  delMonitor: (id) =>
    console.info "Del #{id}"
    delete @monitors[id]

  onEvent: (event) =>
    switch event.status
      when 'start'
        @addMonitor event.id
      when 'die'
        @delMonitor event.id


options = parseArgs process.argv.slice(2)
etcd = null
docker = null
reactor = null

Promise.denodeify(dns.resolveSrv)
  .call(this, process.env.ETCD_DNS_NAME || "etcd.local")
  .then (rr) ->
    etcdServers = rr.map (rr)->"#{rr.name}:#{rr.port}"
    etcdOpts =
      cert: fs.readFileSync process.env.ETCD_SSL_CERT || "etcd-client.crt"
      key:  fs.readFileSync process.env.ETCD_SSL_KEY  || "etcd-client.key"
    etcd = new Etcd etcdServers, etcdOpts
    docker = new Docker socketPath: process.env.DOCKER_SOCK_PATH || '/var/run/docker.sock'
    reactor = new Reactor docker
    Promise.denodeify(docker.listContainers).call(docker)
  .then (list) ->
    console.info list
    list.forEach (info) ->
      reactor.addMonitor info.Id
  .catch (err) ->
    console.error err, err.stack.split '\n'

