package ccc.compute.server.tests;

import haxe.DynamicAccess;
import haxe.io.*;

import haxe.remoting.JsonRpc;

#if (js && !macro)
	import js.node.Buffer;
	import js.npm.shortid.ShortId;

	import util.DockerRegistryTools;
	import util.streams.StreamTools;
#end

import promhx.RequestPromises;
import promhx.deferred.DeferredPromise;

class TestCompute extends ServerAPITestBase
{
	static var TEST_BASE = 'tests';

	@timeout(120000)
	public function testCompleteComputeJobDirect() :Promise<Bool>
	{
		var TESTNAME = 'testCompleteComputeJobDirect';

		var inputValueInline = 'in${ShortId.generate()}';
		var inputName2 = 'in${ShortId.generate()}';
		var inputName3 = 'in${ShortId.generate()}';

		var outputName1 = 'out${ShortId.generate()}';
		var outputName2 = 'out${ShortId.generate()}';
		var outputName3 = 'out${ShortId.generate()}';

		var outputValue1 = 'out${ShortId.generate()}';

		var inputInline :ComputeInputSource = {
			type: InputSource.InputInline,
			value: inputValueInline,
			name: inputName2
		}

		var inputUrl :ComputeInputSource = {
			type: InputSource.InputUrl,
			value: 'https://www.google.com/textinputassistant/tia.png',
			name: inputName3
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
cat /$DIRECTORY_INPUTS/$inputName2 > /$DIRECTORY_OUTPUTS/$outputName2
cat /$DIRECTORY_INPUTS/$inputName3 > /$DIRECTORY_OUTPUTS/$outputName3
';
		var targetStdout = '$outputValueStdout\n$outputValueStdout\nfoo\n$outputValueStdout'.trim();
		var targetStderr = '$outputValueStderr';
		var scriptName = 'script.sh';
		var inputScript :ComputeInputSource = {
			type: InputSource.InputInline,
			value: script,
			name: scriptName
		}

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testReadMultilineStdout/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testReadMultilineStdout/$random/outputs';
		var customResultsPath = '$TEST_BASE/testReadMultilineStdout/$random/results';

		var inputsArray = [inputInline, inputUrl, inputScript];

		var request: BasicBatchProcessRequest = {
			inputs: inputsArray,
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'],
			resultsPath: customResultsPath,
			inputsPath: customInputsPath,
			outputsPath: customOutputsPath
		}

		var forms :DynamicAccess<Dynamic> = {};
		forms[inputUrl.name] = js.npm.request.Request.get(inputUrl.value);

		return ccc.compute.client.ClientTools.postJobWaitOnResult(_serverHost, request, forms)
			.pipe(function(jobResult :JobResult) {
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
							assertTrue(outputs.length == inputsArray.length);
							assertTrue(outputs.has(outputName1));
							assertTrue(outputs.has(outputName2));
							var outputUrl1 = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}/${outputName1}';
							var outputUrl2 = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}/${outputName2}';
							var outputUrl3 = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}/${outputName3}';
							return RequestPromises.get(outputUrl1)
								.pipe(function(out) {
									out = out != null ? out.trim() : out;
									assertEquals(out, outputValue1);
									return RequestPromises.get(outputUrl2)
										.pipe(function(out) {
											out = out != null ? out.trim() : out;
											assertEquals(out, inputValueInline);
											return RequestPromises.getBuffer(outputUrl3)
												.then(function(out) {
													var md5 = js.node.Crypto.createHash('md5').update(out).digest('hex');
													assertEquals(md5, 'ad07ee4cb98da073dda56ce7ceb88f5a');
													return true;
												});
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