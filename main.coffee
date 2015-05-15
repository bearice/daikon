fs = require 'fs'
util = require 'util'
https = require 'https'
URL = require 'url'
EventEmitter = (require 'events').EventEmitter
Transform = require('stream').Transform
JSONStream = require 'JSONStream'

_ = require 'underscore'
split = require 'split'
fibrous = require 'fibrous'
Docker = require 'dockerode'

class MonitorStream
  util.inherits(MonitorStream, Transform)
  constructor: (@container)->
    Transform.call(this, {readableObjectMode:true, objectMode:true})
    @last = null
    @info = @container.sync.inspect()
    @container.sync.stats()
      .pipe(JSONStream.parse())
      .pipe(this)

  _transform: (obj,encoding,cb)->
    if @last
      obj.cpu_stats.percent = @calcCpuUsage obj
      obj.container = @info
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

class EventStream
  constructor: (@docker)->
    return @docker.sync.getEvents()
      .pipe(JSONStream.parse())

docker = new Docker socketPath:process.env.DOCKER_PATH || 'test.sock'
monitors = {}
addMonitor = fibrous (id)->
  c = docker.getContainer id
  m = monitors[id] = new MonitorStream c
  m.on 'data', (obj) ->
    console.info util.format "[%s]: %d",obj.container.Name, obj.cpu_stats.percent.total

main = () ->
  list = docker.sync.listContainers()
  list.forEach (info)->
    addMonitor info.Id, ->
      console.info "Added #{info.Id}"

  es = new EventStream(docker)
  es.on 'data', (event) ->
    console.info event
    switch event.status
      when 'start'
        addMonitor event.id, ->
          console.info "Added #{event.id}"
      when 'die'
        delete monitors[event.id]

fibrous.run main,(err) ->
  throw err if err

