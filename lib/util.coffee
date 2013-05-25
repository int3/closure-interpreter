exports.Util = Util =
  # returns the last item of an array
  last: (arr) -> arr[arr.length - 1]

  # returns the last index that has an object which has key-value pairs that
  # match all of those in :obj.
  lastIndexWhere: (arr, obj) ->
    for a,i in arr by -1
      match = true
      for k, v of obj
        unless k of a and a[k] == v
          match = false
          break
      return i if match
    -1

  defineNonEnumerable: (obj, k, v) ->
    Object.defineProperty obj, k,
      value: v
      writable: true
      enumerable: false
      configurable: true

class exports.Map
  constructor: ->
    @cache = Object.create null
    @proto_cache = undefined
    @proto_set = false

  get: (key) ->
    key = key.toString()
    return @cache[key] unless key is '__proto__'
    return @proto_cache

  has: (key) ->
    key = key.toString()
    return key of @cache unless key is '__proto__'
    return @proto_set

  set: (key, value) ->
    unless key.toString() is '__proto__'
      @cache[key] = value
    else
      @proto_cache = value
      @proto_set = true
    value

  items: ->
    items = ([k,v] for k, v of @cache)
    items.push ['__proto__', @proto_cache] if @proto_set
    items

exports.globalCopy = globalCopy = do ->
  rv = {}
  if global?
    nativeGlobal = global
    globalName = 'global'
  else
    nativeGlobal = window
    globalName = 'window'
  rv[k] = v for k, v of nativeGlobal
  nonEnumerable = ['Object', 'Array', 'String', 'Function', 'RegExp', 'Number',
    'Boolean', 'Date', 'Math', 'Error', 'JSON', 'toString', 'undefined',
    'ReferenceError', 'SyntaxError', 'parseInt', 'parseFloat']
  Util.defineNonEnumerable rv, k, nativeGlobal[k] for k in nonEnumerable
  Util.defineNonEnumerable rv, globalName, rv

exports.RuntimeHelpers =
  ensureThisIsObject: (thisArg) ->
    unless thisArg?
      globalCopy
    else if (t = typeof thisArg) not in ['object', 'function']
      value = new globalCopy[t.charAt(0).toUpperCase() + t[1..]] thisArg
    else
      thisArg

  createArgumentsObject: (argsArray) ->
    argsObject = {}
    argsObject[i] = arg for arg, i in argsArray
    Util.defineNonEnumerable argsObject, 'length', argsArray.length
