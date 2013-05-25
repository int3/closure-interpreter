/*
 * Copyright (C) 2007 Apple Inc.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

var fs = require('fs');
var microtime = require('microtime');
var compile = require('../../../lib/closure-interpreter').compile;

var prefixInfo = JSON.parse(fs.readFileSync(process.argv[2], {encoding:'utf-8'}));
var suiteName = prefixInfo.suiteName;
var tests = prefixInfo.tests;

var results = new Array();

var time = 0;
var times = [];
times.length = tests.length;

function nativeBench()
{
    for (var krakenCounter = 0; krakenCounter < tests.length; krakenCounter++) {    
        var testBase = "../tests/" + suiteName + "/" + tests[krakenCounter];
        var testName = testBase + ".js";
        var startTime = microtime.nowDouble() * 1000;
        require(testName);
        times[krakenCounter] = microtime.nowDouble() * 1000 - startTime;
        gc();
    }
}

function closureInterpreterBench()
{
    var fs = require('fs');
    for (var krakenCounter = 0; krakenCounter < tests.length; krakenCounter++) {    
        var testBase = "tests/" + suiteName + "/" + tests[krakenCounter];
        var testName = testBase + ".js";
        var source = fs.readFileSync(testName, {encoding: 'utf-8'});
        var compiled = compile(source);
        var startTime = microtime.nowDouble() * 1000;
        compiled();
        times[krakenCounter] = microtime.nowDouble() * 1000 - startTime;
        gc();
    }
}

if (process.argv[3] === 'native') {
    nativeBench();
} else if (process.argv[3] === 'closure-interpreter') {
    closureInterpreterBench();
} else {
    throw new Error('Unrecognized evaluator: ' + process.argv[3]);
}

function recordResults(tests, times)
{
    var output = "{\n";

    for (j = 0; j < tests.length; j++) {
        output += '    "' + tests[j] + '": ' + times[j] + ',\n'; 
    }
    output = output.substring(0, output.length - 2) + "\n";

    output += "}";
    console.log(output);
}

recordResults(tests, times);
