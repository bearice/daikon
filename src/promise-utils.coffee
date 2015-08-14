#Promise = require 'promise/lib/es6-extensions'
class PromiseUtils
  @sleep: (time)->
    new Promise (resolve)->
      setTimeout resolve,time

  @seq: (arr, last)=>
    return last unless arr.length
    arr[0](last).then (r)->
      @seq arr.slice(1), r

  @execYields: (gen)=>
    handle = (stat)=>
      if stat.done
        Promise.resolve stat.value
      else
        p = if stat.value and stat.value.constructor.name is 'GeneratorFunctionPrototype'
          @execYields(stat.value)
        else
          Promise.resolve(stat.value)
        p.then (res)->
          handle gen.next(res)
        .catch (e)->
          handle gen.throw(e)
    try
      gen = gen() if gen instanceof Function
      handle gen
    catch e
      console.info e.stack
      Promise.reject e

  @getStreamContent: (stream)->
    new Promise (accept,reject)->
      buf = []
      len = 0
      stream.on 'data', (data) ->
        buf.push data
        len += data.length
      stream.on 'error', (error)->
        buf = Buffer.concat buf,len
        error.buffer = buf
        reject error
      stream.on 'end', ->
        buf = Buffer.concat buf,len
        accept buf

  @ensure: (promise)->
    promise.catch (e)->
      if e.stack
        console.info e.stack
      else
        console.info e
      process.exit 255

module.exports = PromiseUtils

