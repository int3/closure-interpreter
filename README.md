Closure Interpreter
===================

Disclaimer: Just for fun, as an self-educational experiment. Not fit for any
purpose whatsoever. Inspired by Chapter 6 of [LiSP][LiSP], which in turn was based
upon the paper ["Using closures for code generation"][FL87].

This is a JavaScript metacircular "fast interpreter" which removes some of the
interpretive overhead by doing a direct translation of the tree of AST nodes
into a tree of closures. That is, the following (SpiderMonkey- / Esprima-style)
AST snippet

    {
        type: "BinaryExpression"
        operator: "+"
        left: { type: "Identifier", name: "a" }
        right: { type: "Identifier", name: "b" }
    }

gets converted to something like

    function() {
       return (function() {
          return stack[0];
       })() +
       (function() {
          return stack[1];
       })();
    }

This means that we do not need to decode the AST at runtime. Additionally, where
a simpler interpreter would implement variable lookup by checking a series of
hash tables, we speed things up by converting the hash lookups into array
references.

Compared to a full compiler, we still incur a lot of overhead due to the cost of
function calls. Perhaps more importantly, since we do not linearize the AST, we
are still forced to use exceptions for break/continue/return. JS engines do
major deoptimization when encountering exceptions, so this is not great.
Overall, it makes for an approximate 65x slowdown on SunSpider.

On the upside, this "compilation" process is fairly straightforward, and the
resulting code still looks very much like a plain old eval-apply interpreter.

Feature Completeness
--------------------

"Tricky" language bits that have been implemented:

* Hoisting of `var` and `function` declarations
* Direct and indirect `eval` (but without strict mode)
* Immutable bindings (for the identifier of a function expression)

[FL87]: http://www.iro.umontreal.ca/~feeley/papers/FeeleyLapalmeCL87.pdf
[LiSP]: http://www.amazon.com/Lisp-Small-Pieces-Christian-Queinnec/dp/0521545668
