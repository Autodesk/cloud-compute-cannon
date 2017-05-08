package ccc.compute.server.tests;

import ccc.compute.client.js.ClientJSTools;

import haxe.DynamicAccess;
import haxe.io.*;

import haxe.remoting.JsonRpc;

#if (js && !macro)
	import js.node.Buffer;
	import js.npm.shortid.ShortId;

	import util.DockerRegistryTools;
	import util.streams.StreamTools;
#end

import promhx.StreamPromises;
import promhx.RequestPromises;
import promhx.deferred.DeferredPromise;

class TestCompute extends ServerAPITestBase
{
	public static var TEST_BASE = 'tests';
	@inject public var _fs :ServiceStorage;
	@inject public var routes :ccc.compute.server.execution.routes.RpcRoutes;

	@timeout(240000)
	public function testCompleteComputeJobDirect() :Promise<Bool>
	{
		var TESTNAME = 'testCompleteComputeJobDirect';

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_INPUTS';
		var customOutputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_OUTPUTS';
		var customResultsPath = '$TEST_BASE/$TESTNAME/$random/results';

		var inputName2 = 'in${ShortId.generate()}';
		var inputName3 = 'in${ShortId.generate()}';

		var outputName1 = 'out${ShortId.generate()}';
		var outputName2 = 'out${ShortId.generate()}';
		var outputName3 = 'out${ShortId.generate()}';

		var inputValue2 = 'in${ShortId.generate()}';
		var inputValue3 = 'in${ShortId.generate()}';

		var input3Path = '$TEST_BASE/$TESTNAME/$random/${inputName3}';
		var input3Url = 'http://localhost:${SERVER_DEFAULT_PORT}/${input3Path}';

		var outputValue1 = 'out${ShortId.generate()}';

		var inputInline :ComputeInputSource = {
			type: InputSource.InputInline,
			value: inputValue2,
			name: inputName2
		}

		var inputUrl :ComputeInputSource = {
			type: InputSource.InputUrl,
			value: input3Url,
			name: inputName3
		}

		return Promise.promise(true)
			.pipe(function(_) {
				return _fs.writeFile(input3Path, StreamTools.stringToStream(inputValue3));
			})
			.pipe(function(_) {
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
				var customInputsPath = '$TEST_BASE/$TESTNAME/$random/inputs';
				var customOutputsPath = '$TEST_BASE/$TESTNAME/$random/outputs';
				var customResultsPath = '$TEST_BASE/$TESTNAME/$random/results';

				var inputsArray = [inputInline, inputUrl, inputScript];

				var request: BasicBatchProcessRequest = {
					inputs: inputsArray,
					image: DOCKER_IMAGE_DEFAULT,
					cmd: ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'],
					resultsPath: customResultsPath,
					inputsPath: customInputsPath,
					outputsPath: customOutputsPath,
					wait: true,
					priority :true
				}

				var forms :DynamicAccess<Dynamic> = {};
				forms[inputUrl.name] = js.npm.request.Request.get(inputUrl.value);

				var jobId :JobId = null;

				return ClientJSTools.postJob(_serverHost, request, forms)
					.pipe(function(jobResult :JobResultAbstract) {
						if (jobResult == null) {
							throw 'jobResult should not be null. Check the above section';
						}
						jobId = jobResult.jobId;
						return Promise.promise(true)
							.pipe(function(_) {
									assertNotNull(jobResult.stderr);
									var stderrUrl = jobResult.getStderrUrl();
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
									var stdoutUrl = jobResult.getStdoutUrl();
									assertNotNull(stdoutUrl);
									return RequestPromises.get(stdoutUrl)
										.then(function(stdout) {
											stdout = stdout != null ? stdout.trim() : stdout;
											assertEquals(stdout, targetStdout);
											return true;
										});
								})
								.pipe(function(_) {
									var outputs = jobResult.outputs != null ? jobResult.outputs : [];
									assertTrue(outputs.length == inputsArray.length);
									assertTrue(outputs.has(outputName1));
									assertTrue(outputs.has(outputName2));

									var outputUrl1 = jobResult.getOutputUrl(outputName1);
									var outputUrl2 = jobResult.getOutputUrl(outputName2);
									var outputUrl3 = jobResult.getOutputUrl(outputName3);
									return RequestPromises.get(outputUrl1)
										.pipe(function(out) {
											out = out != null ? out.trim() : out;
											assertEquals(out, outputValue1);
											return RequestPromises.get(outputUrl2);
										})
										.pipe(function(out) {
											out = out != null ? out.trim() : out;
											assertEquals(out, inputValue2);
											return RequestPromises.get(outputUrl3);
										})
										.then(function(out) {
											out = out != null ? out.trim() : out;
											assertEquals(out, inputValue3);
											return true;
										});
								})
								.then(function(result) {
									routes.doJobCommand_v2(JobCLICommand.RemoveComplete, jobId)
										.then(function(_) {})
										.catchError(function(err) {
											Log.error({error:err, message:'Failed to remove job $jobId after testCompleteComputeJobDirect'});
										});
									return result;
								});
					});
			});
	}

	public function new()
	{
		super();
	}
}