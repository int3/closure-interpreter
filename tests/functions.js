console.log('testing repeated param names');

function foo(a, b, a) {
  console.log(a, b);
}

foo(1, 2);

console.log('testing function declarations');

function bar(bar) {
  console.log(bar);
}

bar(0);

function barr() {
  console.log(barr);
}

barr();

console.log('testing function expressions');

var x = function barrr() {
  console.log(barrr);
};

x();

x = function barrr() {
  var barrr;
  console.log(barrr);
};

x();

x = function barrr() {
  barrr = 1;
  console.log(barrr);
};

x();


function baz(a) {
  var a;
  console.log(a);
}

baz(-1);

function recursive(i) {
  console.log(i);
  if (i > 0)
    recursive(i - 1);
  console.log(i);
};

recursive(3);

console.log('testing the arguments object');

(function(foo) {
  console.log(arguments);
  console.log(arguments.length);
  arguments.length = 0;
  console.log(arguments.length);
  delete arguments.length;
  console.log(arguments.length);
  console.log(Object.getPrototypeOf(arguments));
})("bar");

(function(arguments) {
  console.log(arguments);
  console.log(arguments.length);
  console.log(Object.getPrototypeOf(arguments));
})({});

(function() {
  console.log(arguments);
  console.log(arguments.length);
})("bar");

(function() {
  var arguments;
  console.log(arguments);
  console.log(arguments.length);
})(1, 2, 3);

(function arguments() {
  console.log(arguments);
  console.log(arguments.length);
})(1, 2, 3);
