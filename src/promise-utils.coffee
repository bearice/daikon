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
      handle gen
    catch e
      console.info e.stack
      Promise.reject e

module.exports = PromiseUtils

