util = require 'util'
{Transform} = require 'stream'
JSONStream = require 'JSONStream'

class DockerStatsStream
  util.inherits(DockerStatsStream, Transform)
  constructor: (@container)->
    Transform.call(this, {readableObjectMode:true, objectMode:true})
    @last = null
    @container.stats().then (stream)=>
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

module.exports = DockerStatsStream

