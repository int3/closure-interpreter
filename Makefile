EVALUATOR := closure-interpreter
TESTS := $(wildcard tests/*.js)
LIB_COFFEE := $(wildcard lib/*.coffee)
LIB_JS := $(LIB_COFFEE:.coffee=.js)

test: $(TESTS:.js=.test) evaluators

evaluators: $(LIB_JS)

benchmarks: sunspider ubench

sunspider: evaluators
	cd vendor/benchmarks && \
	NATIVE=`./sunspider --evaluator=native --suite=sunspider-0.9.1 | tail -n1` \
	INTERP=`./sunspider --evaluator=$(EVALUATOR) --suite=sunspider-0.9.1 | tail -n1` && \
	./sunspider-compare-results $$NATIVE $$INTERP | tee sunspider-results-`git rev-parse --short HEAD`

ubench: evaluators
	cd vendor/benchmarks && \
	NATIVE=`./sunspider --evaluator=native --suite=ubench | tail -n1` \
	NTERP=`./sunspider --evaluator=$(EVALUATOR) --suite=ubench | tail -n1` && \
	./sunspider-compare-results $$NATIVE $$INTERP | tee ubench-results-`git rev-parse --short HEAD`

%.actual: %.js $(LIB_JS)
	@echo "testing $<... \c"
	@node lib/$(EVALUATOR).js $< > $@

%.expected: %.js
	@node $? > $@

%.test: %.actual %.expected
	@diff $?
	@echo "passed"

%.js: %.coffee
	coffee -c $<

.SECONDARY: $(LIB_JS)
