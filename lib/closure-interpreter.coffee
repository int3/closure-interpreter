esprima = require 'esprima'
estraverse = require 'estraverse'
{Util, Map, RuntimeHelpers, globalCopy} = require './util'

# runtime stuff

class ActivationRecord
  constructor: (@staticLink, @thisArg, @vars=[]) ->

activationRecords = [new ActivationRecord null, {}]

class JSException
  constructor: (@exception) ->

class ReturnException
  constructor: (@value) ->

BreakException = {}
ContinueException = {}

evalFn = do ->
  rv = (new Function 'return function eval() {}')()
  Util.defineNonEnumerable rv, '__apply__', (thisArg, args, r=new Environment) ->
    unless typeof args[0] is 'string'
      return args[0]
    (gen esprima.parse(args[0]), r)()

Util.defineNonEnumerable globalCopy, 'eval', evalFn

# compile-time stuff

cg =
  NOP: ->

  _consts: new Map

  genConst: (v) ->
    key = "#{toString.call v}#{if v? then v.toString()}"
    unless @_consts.has key
      @_consts.set key, -> v
    @_consts.get key

  _shallowValues: {}

  genShallowValue: (idx) ->
    @_shallowValues[idx] ?= -> activationRecords[activationRecords.length - 1].vars[idx]

  _shallowRefs: {}

  genShallowRef: (idx) ->
    @_shallowRefs[idx] ?= (v) -> activationRecords[activationRecords.length - 1].vars[idx] = v

  _deepValues: {}

  genDeepValue: (depth, idx) ->
    @_deepValues["#{depth}|#{idx}"] ?= ->
      ar = activationRecords[activationRecords.length - 1]
      for __ in [0...depth] by 1
        ar = ar.staticLink
      ar.vars[idx]

  _deepRefs: {}

  genDeepRef: (depth, idx) ->
    @_deepRefs["#{depth}|#{idx}"] ?= (v) ->
      ar = activationRecords[activationRecords.length - 1]
      for __ in [0...depth] by 1
        ar = ar.staticLink
      ar.vars[idx] = v

  _globalValues: new Map

  genGlobalValue: (name) ->
    unless @_globalValues.has name
      @_globalValues.set name, ->
        if name of globalCopy
          globalCopy[name]
        else
          throw new ReferenceError "#{name} is not defined"
    @_globalValues.get name

  genMemberValue: (objectCode, propertyCode) ->
    -> objectCode()[propertyCode()]

  genAssign: (refCode, valueCode) ->
    -> refCode(valueCode())

  genReturn: (v) -> -> throw new ReturnException v()

class Scope
  constructor: (@vars=[], @strict=false) ->

class Environment
  constructor: (@scopeChain=[new Scope]) ->

  copy: -> new Environment @scopeChain[..]

  increaseScope: (params) ->
    vars = params.map (p) -> {name: p, mutable: true}
    @scopeChain.push new Scope vars, Util.last(@scopeChain).strict

  decreaseScope: -> @scopeChain.pop()

  currentScope: -> Util.last @scopeChain

  declare: (name, mutable=true) ->
    unless (Util.lastIndexWhere (Util.last(@scopeChain).vars), {name, mutable}) >= 0
      Util.last(@scopeChain).vars.push { name, mutable }

  update: (name, init) ->
    for scope,i in @scopeChain by -1
      if (idx = Util.lastIndexWhere scope.vars, {name}) >= 0
        j = @scopeChain.length - i - 1
        if (not scope.vars[idx].mutable) and not init
          return ->
        else if j == 0
          return cg.genShallowRef idx
        else
          return cg.genDeepRef j, idx
    if @currentScope().strict
      -> throw new ReferenceError "#{name} is not defined"
    else
      (v) -> globalCopy[name] = v

  resolve: (name) ->
    for scope,i in @scopeChain by -1
      if (idx = Util.lastIndexWhere scope.vars, {name}) >= 0
        j = @scopeChain.length - i - 1
        if j == 0
          return cg.genShallowValue idx
        else
          return cg.genDeepValue j, idx
    return cg.genGlobalValue name

  has: (name) ->
    for scope in @scopeChain by -1
      if (Util.lastIndexWhere scope.vars, {name}) >= 0
        return true
    false

genMemberExpr = (c, r) ->
  objectCode = gen c.object, r
  if c.property.type is 'Identifier' and not c.computed
    [objectCode, cg.genConst c.property.name]
  else
    propCode = gen c.property, r
    [objectCode, propCode]

genRef = (c, r) ->
  if c.type is 'Identifier'
    r.update c.name
  else if c.type is 'MemberExpression'
    [objectCode, propertyCode] = genMemberExpr c, r
    (v) -> objectCode()[propertyCode()] = v
  else
    throw new Error 'NYI'

genFunction = (c, r) ->
  name = c.id?.name
  paramNames = c.params.map (p) -> p.name
  r.increaseScope(paramNames)
  r.currentScope().strict ||= c.body.body[0]?.expression?.value is 'use strict'
  fnIdCode =
    if c.type is 'FunctionExpression' and name? and name isnt 'arguments'
      r.declare(name, false)
      fnIdAssignCode = r.update name, true
      (fn) -> fnIdAssignCode(fn)
    else
      cg.NOP
  r.declare 'arguments'
  argumentsObjectCode =
    if 'arguments' in paramNames
      cg.NOP
    else
      argumentsAssignCode = r.update 'arguments', true
      (args) -> argumentsAssignCode(RuntimeHelpers.createArgumentsObject args)
  declareVars c.body, r
  hoistedCode = hoistFunctions c.body, r
  initFns = -> fnInit() for fnInit in hoistedCode
  bodyCode = gen c.body, r
  promoteThis =
    if r.currentScope().strict
      (t) -> t
    else
      RuntimeHelpers.ensureThisIsObject
  r.decreaseScope()
  ->
    fn = (new Function "return function #{name ? ''}() {}")()
    ars = activationRecords[..]
    enclosingAr = activationRecords[activationRecords.length - 1]
    Util.defineNonEnumerable fn, '__apply__', (thisArg, args) ->
      oldArs = activationRecords
      activationRecords = ars
      ars.push new ActivationRecord enclosingAr, (promoteThis thisArg), args
      argumentsObjectCode(args) # must create copy before later functions modify args
      fnIdCode(fn)
      initFns()
      try
        bodyCode()
      catch e
        if e instanceof ReturnException
          return e.value
        throw e
      finally
        ars.pop()
        activationRecords = oldArs
    fn

genOperator = (op, a, b) ->
  switch op
    when '+'
      -> a() + b()
    when '-'
      -> a() - b()
    when '*'
      -> a() * b()
    when '/'
      -> a() / b()
    when '%'
      -> a() % b()
    when '^'
      -> a() ^ b()
    when '&'
      -> a() & b()
    when '|'
      -> a() | b()
    when '^'
      -> a() ^ b()
    when '>>'
      -> a() >> b()
    when '<<'
      -> a() << b()
    when '>>>'
      -> a() >>> b()
    when '<'
      -> a() < b()
    when '>'
      -> a() > b()
    when '<='
      -> a() <= b()
    when '>='
      -> a() >= b()
    when '=='
      -> `a() == b()`
    when '==='
      -> a() == b()
    when '!='
      -> `a() != b()`
    when '!=='
      -> a() != b()
    when 'instanceof'
      ->
        try
          a() instanceof b()
        catch e
          throw new JSException e
    else
      throw new Error "Unrecognized operator #{op}"

declareVars = (c, r) ->
  vars = new Map
  estraverse.traverse c,
    enter: (c) ->
      switch c.type
        when 'FunctionDeclaration'
          r.declare c.id.name
          estraverse.VisitorOption.Skip
        when 'FunctionExpression'
          estraverse.VisitorOption.Skip
        when 'VariableDeclarator'
          r.declare c.id.name

hoistFunctions = (c, r) ->
  hoisted = []
  estraverse.traverse c,
    enter: (c) ->
      switch c.type
        when 'FunctionDeclaration'
          refCode = r.update c.id.name
          fnCode = genFunction c, r
          hoisted.push -> refCode(fnCode())
          estraverse.VisitorOption.Skip
        when 'FunctionExpression'
          estraverse.VisitorOption.Skip
  hoisted

gen = (c, r) ->
  if c is null
    return ->
  switch c.type
    when 'Program', 'BlockStatement'
      if c.type is 'Program'
        r.currentScope().strict ||= c.body[0]?.expression?.value is 'use strict'
        declareVars c, r
      stmtCodes = if c.type is 'Program' then hoistFunctions c, r else []
      for stmt in c.body
        stmtCodes.push gen stmt, r
      if c.type is 'Program'
        ->
          for s,i in stmtCodes
            if i is stmtCodes.length - 1
              return s() # for eval's return value
            else
              s()
      else
        -> s() for s in stmtCodes; undefined
    when 'EmptyStatement'
      cg.NOP
    when 'FunctionDeclaration'
      cg.NOP
    when 'FunctionExpression'
      genFunction c, r
    when 'VariableDeclaration'
      decCodes =
        for dec in c.declarations
          gen dec, r
      -> decCodes.map (d) -> d(); undefined
    when 'VariableDeclarator'
      if c.init?
        initCode = gen c.init, r
        refCode = r.update c.id.name, true
        cg.genAssign refCode, initCode
      else
        cg.NOP
    when 'ReturnStatement'
      cg.genReturn(
        if c.argument is null then cg.genConst undefined else gen c.argument, r)
    when 'IfStatement', 'ConditionalExpression'
      testCode = gen c.test, r
      consequentCode = gen c.consequent, r
      alternateCode = if c.alternate? then gen c.alternate, r else ->
      ->
        if testCode()
          consequentCode()
        else
          alternateCode()
    when 'SwitchStatement'
      discriminantCode = gen c.discriminant, r
      DEFAULT = {}
      testCodes =
        for cas in c.cases
          if cas.test isnt null
            gen cas.test, r
          else
            -> DEFAULT
      consequentCodes =
        for cas in c.cases
          stmtCodes = (gen stmt, r for stmt in cas.consequent)
          -> s() for s in stmtCodes
      ->
        discriminant = discriminantCode()
        testValues = testCodes.map (c) -> c()
        for v, i in testValues
          if v is discriminant or v is DEFAULT
            try
              consequentCodes[i]()
            catch e
              if e is BreakException
                break
              else
                throw e
    when 'LogicalExpression'
      lhs = gen c.left, r
      rhs = gen c.right, r
      switch c.operator
        when '&&'
          -> lhs() && rhs()
        when '||'
          -> lhs() || rhs()
        else
          throw new Error 'Unexpected operator'
    when 'WhileStatement'
      testCode = gen c.test, r
      bodyCode = gen c.body, r
      ->
        while testCode()
          try
            bodyCode()
          catch e
            if e == BreakException
              break
            else if e == ContinueException
              continue
            else
              throw e
        return
    when 'DoWhileStatement'
      testCode = gen c.test, r
      bodyCode = gen c.body, r
      ->
        `do {
          try {
            bodyCode();
          } catch (e) {
            if (e === BreakException)
              break
            else if (e === ContinueException)
              continue
            else
              throw e
          }
        } while(testCode())`
        return
    when 'ForStatement'
      initCode = gen c.init, r
      testCode = gen c.test, r
      updateCode = gen c.update, r
      bodyCode = gen c.body, r
      ->
        `for (initCode(); testCode(); updateCode()) {
            try {
              bodyCode();
            } catch (e) {
              if (e === BreakException)
                break
              else if (e === ContinueException)
                continue
              else
                throw e
            }
        }`
        return
    when 'ForInStatement'
      left =
        if c.left.type is 'VariableDeclaration'
          c.left.declarations[0].id
        else
          c.left
      refCode = genRef left, r
      objCode = gen c.right, r
      bodyCode = gen c.body, r
      ->
        for k of objCode()
          refCode(k)
          try
            bodyCode()
          catch e
            if e == BreakException
              break
            else if e == ContinueException
              continue
            else
              throw e
        return
    when 'BreakStatement'
      -> throw BreakException
    when 'ContinueStatement'
      -> throw ContinueException
    when 'TryStatement'
      blockCode = gen c.block, r
      if c.handlers.length > 0
        r.increaseScope([c.handlers[0].param.name])
        handlerBodyCode = gen c.handlers[0], r
        r.decreaseScope()
        handlerCode = (e) ->
          if e instanceof JSException
            ar = new ActivationRecord activationRecords[activationRecords.length - 1]
            activationRecords.push ar
            ar.vars.push e.exception
            handlerBodyCode()
            activationRecords.pop()
          else
            throw e
      else
        handlerCode = (e) -> throw e
      finalizerCode = if c.finalizer? then gen c.finalizer, r else ->
      ->
        try
          blockCode()
        catch e
          handlerCode(e)
        finally
          finalizerCode()
    when 'CatchClause'
      gen c.body, r
    when 'ThrowStatement'
      exceptionCode = gen c.argument, r
      -> throw new JSException exceptionCode()
    when 'ExpressionStatement'
      gen c.expression, r
    when 'AssignmentExpression'
      right = gen c.right, r
      refCode = genRef c.left, r
      if c.operator is '='
        -> refCode(right())
      else
        left = gen c.left, r
        valueCode = genOperator(c.operator[...-1], left, right)
        -> refCode(valueCode())
    when 'CallExpression'
      if c.callee.type is 'MemberExpression'
        [thisCode, propertyCode] = genMemberExpr c.callee, r
        calleeCode = cg.genMemberValue thisCode, propertyCode
      else
        thisCode = cg.genConst undefined
        if c.callee.name is 'eval'
          directEval = true
        else
          calleeCode = gen c.callee, r
      argCode = (gen arg, r for arg in c.arguments)
      unless directEval
        ->
          callee = calleeCode()
          args = argCode.map (a) -> a()
          if callee.__apply__?
            callee.__apply__ thisCode(), args
          else
            try
              callee.apply thisCode(), args
            catch e
              throw new JSException e
      else
        rCopy = r.copy()
        ->
          args = argCode.map (a) -> a()
          evalFn.__apply__ thisCode(), args, rCopy
    when 'NewExpression'
      calleeCode = gen c.callee, r
      argCode = (gen arg, r for arg in c.arguments)
      ->
        callee = calleeCode()
        args = argCode.map (a) -> a()
        if callee.__apply__?
          obj = new callee
          callee.__apply__ obj, args
        else
          obj = new (callee.bind.apply callee, [null].concat args)
        obj
    when 'BinaryExpression'
      genOperator c.operator, (gen c.left, r), (gen c.right, r)
    when 'UnaryExpression'
      if c.operator is 'delete'
        if c.argument.type is 'MemberExpression'
          [objectCode, propertyCode] = genMemberExpr c.argument, r
          -> delete objectCode()[propertyCode()]
        else
          throw new Error 'NYI'
      else if c.operator is 'typeof' and
          c.argument.type is 'Identifier' and not r.has c.argument.name
        cg.genConst 'undefined'
      else
        argCode = gen c.argument, r
        switch c.operator
          when '-'
            -> -argCode()
          when '~'
            -> ~argCode()
          when '!'
            -> !argCode()
          when 'typeof'
            -> typeof argCode()
          else
            throw new Error 'NYI'
    when 'UpdateExpression'
      argCode = gen c.argument, r
      refCode = genRef c.argument, r
      newValueCode =
        if c.operator is '++'
          -> argCode() + 1
        else # '--'
          -> argCode() - 1
      if c.prefix
        cg.genAssign refCode, newValueCode
      else
        ->
          original = argCode()
          refCode(newValueCode())
          original
    when 'Identifier'
      r.resolve c.name
    when 'ThisExpression'
      -> activationRecords[activationRecords.length - 1].thisArg
    when 'MemberExpression'
      cg.genMemberValue.apply cg, genMemberExpr c, r
    when 'Literal'
      cg.genConst c.value
    when 'ObjectExpression'
      kvCodes =
        for prop in c.properties
          do (prop = prop) ->
            {
              key: if prop.key.name then prop.key.name else prop.key.value
              value: gen prop.value, r
            }
      ->
        obj = {}
        for codes in kvCodes
          obj[codes.key] = codes.value()
        obj
    when 'ArrayExpression'
      elementCodes =
        for el in c.elements
          gen el, r
      -> elementCodes.map (e) -> e()
    else
      throw new Error "NYI: #{c.type}"

exports.compile = compile = (src) -> gen (esprima.parse src), new Environment

if require.main is module
  fs = require 'fs'
  (compile fs.readFileSync process.argv[2], encoding: 'utf-8')()
