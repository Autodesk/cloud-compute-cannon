package ccc.compute.server.tests;

import haxe.DynamicAccess;
import haxe.io.*;

import haxe.remoting.JsonRpc;

import js.node.Buffer;
import js.npm.shortid.ShortId;

import promhx.RequestPromises;
import promhx.deferred.DeferredPromise;

import util.DockerRegistryTools;
import util.streams.StreamTools;

class TestCompute extends ServerAPITestBase
{
	static var TEST_BASE = 'tests';

	@timeout(120000)
	public function testCompleteComputeJob() :Promise<Bool>
	{
		var TESTNAME = 'testAll';
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);

		var inputValue = 'in${ShortId.generate()}';
		var inputName = 'in${ShortId.generate()}';

		var outputName1 = 'out${ShortId.generate()}';
		var outputName2 = 'out${ShortId.generate()}';
		var outputValue1 = 'out${ShortId.generate()}';

		var input :ComputeInputSource = {
			type: InputSource.InputInline,
			value: inputValue,
			name: inputName
		}
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_INPUTS';
		var customOutputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_OUTPUTS';
		var customResultsPath = '$TEST_BASE/$TESTNAME/$random/results';

		var outputValueStdout = 'out${ShortId.generate()}';
		var outputValueStderr = 'out${ShortId.generate()}';
		//Multiline stdout
		var script =
'#!/bin/sh
echo "$outputValueStdout"
echo "$outputValueStdout"
echo foo
echo "$outputValueStdout"
echo "$outputValueStderr" >> /dev/stderr
echo "$outputValue1" > /$DIRECTORY_OUTPUTS/$outputName1
cat /$DIRECTORY_INPUTS/$inputName > /$DIRECTORY_OUTPUTS/$outputName2
';
		var targetStdout = '$outputValueStdout\n$outputValueStdout\nfoo\n$outputValueStdout'.trim();
		var targetStderr = '$outputValueStderr';
		var scriptName = 'script.sh';
		var inputScript :ComputeInputSource = {
			type: InputSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testReadMultilineStdout/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testReadMultilineStdout/$random/outputs';
		var customResultsPath = '$TEST_BASE/testReadMultilineStdout/$random/results';

		return proxy.submitJob('busybox', ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input, inputScript], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				return Promise.promise(true)
					.pipe(function(_) {
							assertNotNull(jobResult.stderr);
							var stderrUrl = 'http://${SERVER_LOCAL_HOST}/${jobResult.stderr}';
							assertNotNull(stderrUrl);
							return RequestPromises.get(stderrUrl)
								.then(function(stderr) {
									stderr = stderr != null ? stderr.trim() : stderr;
									assertEquals(stderr, targetStderr);
									return true;
								});
						})
						.pipe(function(_) {
							assertNotNull(jobResult.stdout);
							var stdoutUrl = 'http://${SERVER_LOCAL_HOST}/${jobResult.stdout}';
							assertNotNull(stdoutUrl);
							return RequestPromises.get(stdoutUrl)
								.then(function(stdout) {
									stdout = stdout != null ? stdout.trim() : stdout;
									assertEquals(stdout, targetStdout);
									return true;
								});
						})
						.pipe(function(_) {
							var outputUrl = jobResult.outputsBaseUrl;
							var outputs = jobResult.outputs != null ? jobResult.outputs : [];
							assertTrue(outputs.length == 2);
							assertTrue(outputs.has(outputName1));
							assertTrue(outputs.has(outputName2));
							var outputUrl1 = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}/${outputName1}';
							var outputUrl2 = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}/${outputName2}';
							return RequestPromises.get(outputUrl1)
								.pipe(function(out) {
									out = out != null ? out.trim() : out;
									assertEquals(out, outputValue1);
									return RequestPromises.get(outputUrl2)
										.then(function(out) {
											out = out != null ? out.trim() : out;
											assertEquals(out, inputValue);
											return true;
										});
								});
						});
			});
	}

	public function new(targetHost :Host)
	{
		super(targetHost);
	}
}