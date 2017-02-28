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

class TestJobs extends ServerAPITestBase
{
	static var TEST_BASE = 'tests';

	@timeout(120000)
	public function testExitCodeZero() :Promise<Bool>
	{
		var script =
'#!/bin/sh
exit 0
';
		var scriptName = 'script.sh';
		var input :ComputeInputSource = {
			type: InputSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testExitCodeZero/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testExitCodeZero/$random/outputs';
		var customResultsPath = '$TEST_BASE/testExitCodeZero/$random/results';

		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.then(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				assertEquals(jobResult.exitCode, 0);
				return true;
			});
	}

	@timeout(120000)
	public function testExitCodeNonZeroScript() :Promise<Bool>
	{
		var exitCode = 3;
		var script =
'#!/bin/sh
exit $exitCode
';
		var scriptName = 'script.sh';
		var input :ComputeInputSource = {
			type: InputSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testExitCodeNonZeroScript/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testExitCodeNonZeroScript/$random/outputs';
		var customResultsPath = '$TEST_BASE/testExitCodeNonZeroScript/$random/results';

		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.then(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				assertEquals(jobResult.exitCode, exitCode);
				return true;
			});
	}

	@timeout(120000)
	public function testExitCodeNonZeroCommand() :Promise<Bool>
	{
		var exitCode = 4;
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testExitCodeNonZeroCommand/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testExitCodeNonZeroCommand/$random/outputs';
		var customResultsPath = '$TEST_BASE/testExitCodeNonZeroCommand/$random/results';

		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '-c', 'exit $exitCode'], [], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.then(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				assertEquals(jobResult.exitCode, exitCode);
				return true;
			});
	}

	@timeout(120000)
	public function testWaitForJob() :Promise<Bool>
	{
		var outputValueStdout = 'out${ShortId.generate()}';
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var waitForJobToFinish = true;
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testWaitForJob/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testWaitForJob/$random/outputs';
		var customResultsPath = '$TEST_BASE/testWaitForJob/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '-c', 'echo $outputValueStdout'], [], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath, waitForJobToFinish)
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				return Promise.promise(true)
					.pipe(function(_) {
						assertNotNull(jobResult.stdout);
						var stdoutUrl = jobResult.getStdoutUrl();
						assertNotNull(stdoutUrl);
						return RequestPromises.get(stdoutUrl)
							.then(function(stdout) {
								stdout = stdout != null ? stdout.trim() : stdout;
								assertEquals(stdout, outputValueStdout);
								return true;
							});
					});
			});
	}

	@timeout(120000)
	public function testReadMultilineStdout() :Promise<Bool>
	{
		var outputValueStdout = 'out${ShortId.generate()}';
		var script =
'#!/bin/sh
echo "$outputValueStdout"
echo "$outputValueStdout"
echo foo
echo "$outputValueStdout"
';
		var compareOutput = '$outputValueStdout\n$outputValueStdout\nfoo\n$outputValueStdout'.trim();
		var scriptName = 'script.sh';
		var input :ComputeInputSource = {
			type: InputSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testReadMultilineStdout/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testReadMultilineStdout/$random/outputs';
		var customResultsPath = '$TEST_BASE/testReadMultilineStdout/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}

				return Promise.promise(true)
					.pipe(function(_) {
						assertNotNull(jobResult.stdout);
						var stdoutUrl = jobResult.getStdoutUrl();
						assertNotNull(stdoutUrl);
						return RequestPromises.get(stdoutUrl)
							.then(function(stdout) {
								stdout = stdout != null ? stdout.trim() : stdout;
								assertEquals(stdout, compareOutput);
								return true;
							});
					});
			});
	}

	@timeout(120000)
	public function testWriteStdoutAndStderr() :Promise<Bool>
	{
		var outputValueStdout = 'out${ShortId.generate()}';
		var outputValueStderr = 'out${ShortId.generate()}';
		var script =
'#!/bin/sh
echo "$outputValueStdout"
echo "$outputValueStderr" >>/dev/stderr
';
		var scriptName = 'script.sh';
		var input :ComputeInputSource = {
			type: InputSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testWriteStdoutAndStderr/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testWriteStdoutAndStderr/$random/outputs';
		var customResultsPath = '$TEST_BASE/testWriteStdoutAndStderr/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}

				return Promise.promise(true)
					.pipe(function(_) {
						assertNotNull(jobResult.stderr);
						var stderrUrl = jobResult.getStderrUrl();
						assertNotNull(stderrUrl);
						return RequestPromises.get(stderrUrl)
							.then(function(stderr) {
								stderr = stderr != null ? stderr.trim() : stderr;
								assertEquals(stderr, outputValueStderr);
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
								assertEquals(stdout, outputValueStdout);
								return true;
							});
					});
			});
	}

	@timeout(120000)
	public function testReadInput() :Promise<Bool>
	{
		var inputValue = 'in${Std.int(Math.random() * 100000000)}';
		var inputName = 'in${Std.int(Math.random() * 100000000)}';
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var input :ComputeInputSource = {
			type: InputSource.InputInline,
			value: inputValue,
			name: inputName
		}
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testReadInput/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testReadInput/$random/outputs';
		var customResultsPath = '$TEST_BASE/testReadInput/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["cat", '/$DIRECTORY_INPUTS/$inputName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var stdOutUrl = jobResult.getStdoutUrl();
				assertNotNull(stdOutUrl);
				return RequestPromises.get(stdOutUrl)
					.then(function(stdout) {
						assertNotNull(stdout);
						stdout = stdout.trim();
						assertEquals(stdout.length, inputValue.length);
						assertEquals(stdout, inputValue);
						return true;
					});
			});
	}

	@timeout(120000)
	public function testWriteOutput() :Promise<Bool>
	{
		var outputValue = 'out${Std.int(Math.random() * 100000000)}';
		var outputName = 'out${Std.int(Math.random() * 100000000)}';
		var script =
'#!/bin/sh
echo "$outputValue" > /$DIRECTORY_OUTPUTS/$outputName
';
		var scriptName = 'script.sh';
		var input :ComputeInputSource = {
			type: InputSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testWriteOutput/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testWriteOutput/$random/outputs';
		var customResultsPath = '$TEST_BASE/testWriteOutput/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var outputs = jobResult.outputs != null ? jobResult.outputs : [];
				assertTrue(outputs.length == 1);
				var outputUrl = jobResult.getOutputUrl(outputs[0]);
				return RequestPromises.get(outputUrl)
					.then(function(out) {
						out = out != null ? out.trim() : out;
						assertEquals(out, outputValue);
						return true;
					});
			});
	}

	@timeout(120000)
	public function testBinaryInputAndOutput() :Promise<Bool>
	{
		// Create bytes for inputs. We'll test the output bytes
		// against these
		var bytes1 = new Buffer([Std.int(Math.random() * 1000), Std.int(Math.random() * 1000), Std.int(Math.random() * 1000)]);
		var inputName1 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName1 = 'out${Std.int(Math.random() * 100000000)}';

		var inputBinaryValue1 :ComputeInputSource = {
			type: InputSource.InputInline,
			value: bytes1.toString('base64'),
			name: inputName1,
			encoding: InputEncoding.base64
		}

		var bytes2 = new Buffer('somestring${Std.int(Math.random() * 100000000)}', 'utf8');
		var inputName2 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName2 = 'out${Std.int(Math.random() * 100000000)}';

		var inputBinaryValue2 :ComputeInputSource = {
			type: InputSource.InputInline,
			value: bytes2.toString('base64'),
			name: inputName2,
			encoding: InputEncoding.base64
		}

		//A script that copies the inputs to outputs
		var script =
'#!/bin/sh
cp /$DIRECTORY_INPUTS/$inputName1 /$DIRECTORY_OUTPUTS/$outputName1
cp /$DIRECTORY_INPUTS/$inputName2 /$DIRECTORY_OUTPUTS/$outputName2
';
		var scriptName = 'script.sh';
		var inputScript :ComputeInputSource = {
			type: InputSource.InputInline,
			value: script,
			name: scriptName,
			encoding: InputEncoding.utf8 //Default
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/outputs';
		var customResultsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/results';
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [inputScript, inputBinaryValue1, inputBinaryValue2], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var outputs = jobResult.outputs != null ? jobResult.outputs : [];
				assertTrue(outputs.length == 2);
				var outputUrl1 = jobResult.getOutputUrl(outputName1);
				return RequestPromises.getBuffer(outputUrl1)
					.pipe(function(out1) {
						assertNotNull(out1);
						assertEquals(out1.compare(bytes1), 0);
						var outputUrl2 = jobResult.getOutputUrl(outputName2);
						return RequestPromises.getBuffer(outputUrl2)
							.then(function(out2) {
								assertNotNull(out2);
								assertEquals(out2.compare(bytes2), 0);
								return true;
							});
					});
			});
	}

	@timeout(120000)
	public function testMultipartRPCSubmission() :Promise<Bool>
	{
		var url = 'http://${_serverHost}${SERVER_RPC_URL}';

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/outputs';
		var customResultsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/results';

		// Create bytes for inputs. We'll test the output bytes
		// against these
		var bytes1 = new Buffer([Std.int(Math.random() * 1000), Std.int(Math.random() * 1000), Std.int(Math.random() * 1000)]);
		var inputName1 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName1 = 'out${Std.int(Math.random() * 100000000)}';

		var bytes2 = new Buffer('somestring${Std.int(Math.random() * 100000000)}', 'utf8');
		var inputName2 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName2 = 'out${Std.int(Math.random() * 100000000)}';

		//A script that copies the inputs to outputs
		var script =
'#!/bin/sh
cp /$DIRECTORY_INPUTS/$inputName1 /$DIRECTORY_OUTPUTS/$outputName1
cp /$DIRECTORY_INPUTS/$inputName2 /$DIRECTORY_OUTPUTS/$outputName2
';
		var scriptName = 'script.sh';

		var jobSubmissionOptions :BasicBatchProcessRequest = {
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ['/bin/sh', '/$DIRECTORY_INPUTS/$scriptName'],
			inputs: [], //inputs are part of the multipart message (formStreams)
			parameters: {cpus:1, maxDuration:20*60*100000},
			//Custom paths
			outputsPath: customOutputsPath,
			inputsPath: customInputsPath,
			resultsPath: customResultsPath,
		};

		var formData :DynamicAccess<Dynamic> = {};
		formData[JsonRpcConstants.MULTIPART_JSONRPC_KEY] = Json.stringify(
			{
				method: RPC_METHOD_JOB_SUBMIT,
				params: jobSubmissionOptions,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2

			});
		formData[scriptName] = script;
		formData[inputName1] = bytes1;
		formData[inputName2] = bytes2;

		var promise = new DeferredPromise();
		js.npm.request.Request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					promise.boundPromise.reject(err);
					return;
				}
				if (httpResponse.statusCode == 200) {
					try {
						Promise.promise(true)
							.pipe(function(out) {
								var jobIdResult :{result:{jobId:String}} = Json.parse(body);
								return ServerTestTools.getJobResult(jobIdResult.result.jobId);
							})
							.pipe(function(jobResult :JobResultAbstract) {
								if (jobResult == null) {
									throw 'jobResult should not be null. Check the above section';
								}
								var outputs = jobResult.outputs != null ? jobResult.outputs : [];
								assertEquals(outputs.length, 2);
								var outputUrl1 = jobResult.getOutputUrl(outputName1);
								return RequestPromises.getBuffer(outputUrl1)
									.pipe(function(out1) {
										assertNotNull(out1);
										assertEquals(out1.compare(bytes1), 0);
										var outputUrl2 = jobResult.getOutputUrl(outputName2);
										return RequestPromises.getBuffer(outputUrl2)
											.then(function(out2) {
												assertNotNull(out2);
												assertEquals(out2.compare(bytes2), 0);
												return true;
											});
									});
							})
							.then(function(passed) {
								promise.resolve(passed);
							});
					} catch (err :Dynamic) {
						promise.boundPromise.reject(err);
					}
				} else {
					promise.boundPromise.reject('non-200 response body=' + body);
				}
			});

		return promise.boundPromise;
	}

	@timeout(120000)
	public function testMultipartRPCSubmissionAndWait() :Promise<Bool>
	{
		var url = 'http://${_serverHost}${SERVER_RPC_URL}';

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/outputs';
		var customResultsPath = '$TEST_BASE/testBinaryInputAndOutput/$random/results';

		// Create bytes for inputs. We'll test the output bytes
		// against these
		var bytes1 = new Buffer([Std.int(Math.random() * 1000), Std.int(Math.random() * 1000), Std.int(Math.random() * 1000)]);
		var inputName1 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName1 = 'out${Std.int(Math.random() * 100000000)}';

		var bytes2 = new Buffer('somestring${Std.int(Math.random() * 100000000)}', 'utf8');
		var inputName2 = 'in${Std.int(Math.random() * 100000000)}';
		var outputName2 = 'out${Std.int(Math.random() * 100000000)}';

		//A script that copies the inputs to outputs
		var script =
'#!/bin/sh
cp /$DIRECTORY_INPUTS/$inputName1 /$DIRECTORY_OUTPUTS/$outputName1
cp /$DIRECTORY_INPUTS/$inputName2 /$DIRECTORY_OUTPUTS/$outputName2
';
		var scriptName = 'script.sh';

		var jobSubmissionOptions :BasicBatchProcessRequest = {
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ['/bin/sh', '/$DIRECTORY_INPUTS/$scriptName'],
			inputs: [], //inputs are part of the multipart message (formStreams)
			parameters: {cpus:1, maxDuration:20*60*100000},
			//Custom paths
			outputsPath: customOutputsPath,
			inputsPath: customInputsPath,
			resultsPath: customResultsPath,
			wait: true
		};

		var formData :DynamicAccess<Dynamic> = {};
		formData[JsonRpcConstants.MULTIPART_JSONRPC_KEY] = Json.stringify(
			{
				method: RPC_METHOD_JOB_SUBMIT,
				params: jobSubmissionOptions,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2

			});
		formData[scriptName] = script;
		formData[inputName1] = bytes1;
		formData[inputName2] = bytes2;

		var promise = new DeferredPromise();
		js.npm.request.Request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					promise.boundPromise.reject(err);
					return;
				}
				if (httpResponse.statusCode == 200) {
					try {
						Promise.promise(true)
							.then(function(out) {
								var rpcResult :{result:JobResult} = Json.parse(body);
								return rpcResult.result;
							})
							.pipe(function(jobResult :JobResultAbstract) {
								if (jobResult == null) {
									throw 'jobResult should not be null. Check the above section';
								}
								var outputs = jobResult.outputs != null ? jobResult.outputs : [];
								assertEquals(outputs.length, 2);
								var outputUrl1 = jobResult.getOutputUrl(outputName1);
								return RequestPromises.getBuffer(outputUrl1)
									.pipe(function(out1) {
										assertNotNull(out1);
										assertEquals(out1.compare(bytes1), 0);
										var outputUrl2 = jobResult.getOutputUrl(outputName2);
										return RequestPromises.getBuffer(outputUrl2)
											.then(function(out2) {
												assertNotNull(out2);
												assertEquals(out2.compare(bytes2), 0);
												return true;
											});
									});
							})
							.then(function(passed) {
								promise.resolve(passed);
							});
					} catch (err :Dynamic) {
						promise.boundPromise.reject(err);
					}
				} else {
					promise.boundPromise.reject('non-200 response body=' + body);
				}
			});

		return promise.boundPromise;
	}

	@timeout(120000)
	public function testMultipartRPCSubmissionAndWaitNonZeroExitCode() :Promise<Bool>
	{
		var url = 'http://${_serverHost}${SERVER_RPC_URL}';
		var exitCode = 3;
		var script =
'#!/bin/sh
exit $exitCode
';
		var scriptName = 'script.sh';

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testMultipartRPCSubmissionAndWaitNonZeroExitCode/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testMultipartRPCSubmissionAndWaitNonZeroExitCode/$random/outputs';
		var customResultsPath = '$TEST_BASE/testMultipartRPCSubmissionAndWaitNonZeroExitCode/$random/results';

		var jobSubmissionOptions :BasicBatchProcessRequest = {
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ['/bin/sh', '/$DIRECTORY_INPUTS/$scriptName'],
			inputs: [],
			parameters: {cpus:1, maxDuration:20*60*100000},
			outputsPath: customOutputsPath,
			inputsPath: customInputsPath,
			resultsPath: customResultsPath,
			wait: true
		};

		var formData :DynamicAccess<Dynamic> = {};
		formData[JsonRpcConstants.MULTIPART_JSONRPC_KEY] = Json.stringify(
			{
				method: RPC_METHOD_JOB_SUBMIT,
				params: jobSubmissionOptions,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2

			});
		formData[scriptName] = script;

		var promise = new DeferredPromise();
		js.npm.request.Request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					promise.boundPromise.reject(err);
					return;
				}
				if (httpResponse.statusCode == 200) {
					try {
						Promise.promise(true)
							.then(function(out) {
								var rpcResult :{result:JobResult} = Json.parse(body);
								return rpcResult.result;
							})
							.then(function(jobResult :JobResultAbstract) {
								if (jobResult == null) {
									throw 'jobResult should not be null. Check the above section';
								}
								return true;
							})
							.then(function(passed) {
								promise.resolve(passed);
							});
					} catch (err :Dynamic) {
						promise.boundPromise.reject(err);
					}
				} else {
					promise.boundPromise.reject('non-200 response body=' + body);
				}
			});

		return promise.boundPromise;
	}

	@timeout(120000)
	public function testMultipartRPCSubmissionBadDockerImage() :Promise<Bool>
	{
		var url = 'http://${_serverHost}${SERVER_RPC_URL}';
		var script =
'#!/bin/sh
exit 0
';
		var scriptName = 'script.sh';

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/testMultipartRPCSubmissionBadDockerImage/$random/inputs';
		var customOutputsPath = '$TEST_BASE/testMultipartRPCSubmissionBadDockerImage/$random/outputs';
		var customResultsPath = '$TEST_BASE/testMultipartRPCSubmissionBadDockerImage/$random/results';

		var jobSubmissionOptions :BasicBatchProcessRequest = {
			image: 'this_docker_image_is_fubar',
			cmd: ['/bin/sh', '/$DIRECTORY_INPUTS/$scriptName'],
			inputs: [],
			parameters: {cpus:1, maxDuration:20*60*100000},
			outputsPath: customOutputsPath,
			inputsPath: customInputsPath,
			resultsPath: customResultsPath,
			wait: true
		};

		var formData :DynamicAccess<Dynamic> = {};
		formData[JsonRpcConstants.MULTIPART_JSONRPC_KEY] = Json.stringify(
			{
				method: RPC_METHOD_JOB_SUBMIT,
				params: jobSubmissionOptions,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2

			});
		formData[scriptName] = script;

		var promise = new DeferredPromise();
		js.npm.request.Request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					promise.boundPromise.reject(err);
					return;
				}
				traceCyan('httpResponse.statusCode=${httpResponse.statusCode}');
				promise.resolve(httpResponse.statusCode == 400);
			});

		return promise.boundPromise;
	}

// 	@timeout(120000)
// 	public function testCompleteComputeJobProxy() :Promise<Bool>
// 	{
// 		var TESTNAME = 'testCompleteComputeJobProxy';

// 		var inputValueInline = 'in${ShortId.generate()}';
// 		var inputName2 = 'in${ShortId.generate()}';
// 		var inputName3 = 'in${ShortId.generate()}';

// 		var outputName1 = 'out${ShortId.generate()}';
// 		var outputName2 = 'out${ShortId.generate()}';
// 		var outputName3 = 'out${ShortId.generate()}';

// 		var outputValue1 = 'out${ShortId.generate()}';

// 		var inputInline :ComputeInputSource = {
// 			type: InputSource.InputInline,
// 			value: inputValueInline,
// 			name: inputName2
// 		}

// 		var inputUrl :ComputeInputSource = {
// 			type: InputSource.InputUrl,
// 			value: 'https://www.google.com/textinputassistant/tia.png',
// 			name: inputName3
// 		}

// 		var random = ShortId.generate();
// 		var customInputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_INPUTS';
// 		var customOutputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_OUTPUTS';
// 		var customResultsPath = '$TEST_BASE/$TESTNAME/$random/results';

// 		var outputValueStdout = 'out${ShortId.generate()}';
// 		var outputValueStderr = 'out${ShortId.generate()}';
// 		//Multiline stdout
// 		var script =
// '#!/bin/sh
// echo "$outputValueStdout"
// echo "$outputValueStdout"
// echo foo
// echo "$outputValueStdout"
// echo "$outputValueStderr" >> /dev/stderr
// echo "$outputValue1" > /$DIRECTORY_OUTPUTS/$outputName1
// cat /$DIRECTORY_INPUTS/$inputName2 > /$DIRECTORY_OUTPUTS/$outputName2
// cat /$DIRECTORY_INPUTS/$inputName3 > /$DIRECTORY_OUTPUTS/$outputName3
// ';
// 		var targetStdout = '$outputValueStdout\n$outputValueStdout\nfoo\n$outputValueStdout'.trim();
// 		var targetStderr = '$outputValueStderr';
// 		var scriptName = 'script.sh';
// 		var inputScript :ComputeInputSource = {
// 			type: InputSource.InputInline,
// 			value: script,
// 			name: scriptName
// 		}

// 		var inputsArray = [inputInline, inputUrl, inputScript];
// 		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
// 		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], inputsArray, null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
// 			.pipe(function(out) {
// 				return ServerTestTools.getJobResult(out.jobId);
// 			})
// 			.pipe(function(jobResult :JobResultAbstract) {
// 				if (jobResult == null) {
// 					throw 'jobResult should not be null. Check the above section';
// 				}
// 				return Promise.promise(true)
// 					.pipe(function(_) {
// 							assertNotNull(jobResult.stderr);
// 							var stderrUrl = jobResult.getStderrUrl();
// 							assertNotNull(stderrUrl);
// 							return RequestPromises.get(stderrUrl)
// 								.then(function(stderr) {
// 									stderr = stderr != null ? stderr.trim() : stderr;
// 									assertEquals(stderr, targetStderr);
// 									return true;
// 								});
// 						})
// 						.pipe(function(_) {
// 							assertNotNull(jobResult.stdout);
// 							var stdoutUrl = jobResult.getStdoutUrl();
// 							assertNotNull(stdoutUrl);
// 							return RequestPromises.get(stdoutUrl)
// 								.then(function(stdout) {
// 									stdout = stdout != null ? stdout.trim() : stdout;
// 									assertEquals(stdout, targetStdout);
// 									return true;
// 								});
// 						})
// 						.pipe(function(_) {
// 							var outputs = jobResult.outputs != null ? jobResult.outputs : [];
// 							assertTrue(outputs.length == inputsArray.length);
// 							assertTrue(outputs.has(outputName1));
// 							assertTrue(outputs.has(outputName2));
// 							var outputUrl1 = jobResult.getOutputUrl(outputName1);
// 							var outputUrl2 = jobResult.getOutputUrl(outputName2);
// 							var outputUrl3 = jobResult.getOutputUrl(outputName3);
// 							return RequestPromises.get(outputUrl1)
// 								.pipe(function(out) {
// 									out = out != null ? out.trim() : out;
// 									assertEquals(out, outputValue1);
// 									return RequestPromises.get(outputUrl2)
// 										.pipe(function(out) {
// 											out = out != null ? out.trim() : out;
// 											assertEquals(out, inputValueInline);
// 											return RequestPromises.getBuffer(outputUrl3)
// 												.then(function(out) {
// 													var md5 = js.node.Crypto.createHash('md5').update(out).digest('hex');
// 													assertTrue(md5 == 'ad07ee4cb98da073dda56ce7ceb88f5a' || md5 == '201e50d8dd7a30c0a918213686ca43b7');
// 													return true;
// 												});
// 										});
// 								});
// 						});
// 			});
// 	}

	public function new(targetHost :Host)
	{
		super(targetHost != null ? targetHost : new Host(new HostName('localhost'), new Port(SERVER_DEFAULT_PORT)));
	}
}