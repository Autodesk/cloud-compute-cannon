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
		return proxy.submitJob('busybox', ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}

				return Promise.promise(true)
					.pipe(function(_) {
						assertNotNull(jobResult.stdout);
						var stdoutUrl = 'http://${SERVER_LOCAL_HOST}/${jobResult.stdout}';
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
		return proxy.submitJob('busybox', ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
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
								assertEquals(stderr, outputValueStderr);
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
		return proxy.submitJob('busybox', ["cat", '/$DIRECTORY_INPUTS/$inputName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var stdOutUrl = 'http://${SERVER_LOCAL_HOST}/${jobResult.stdout}';
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
		return proxy.submitJob('busybox', ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var outputUrl = jobResult.outputsBaseUrl;
				var outputs = jobResult.outputs != null ? jobResult.outputs : [];
				assertTrue(outputs.length == 1);
				var outputUrl = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}/${outputs[0]}';
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
		return proxy.submitJob('busybox', ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [inputScript, inputBinaryValue1, inputBinaryValue2], null, 1, 600000, customResultsPath, customInputsPath, customOutputsPath)
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var outputUrl = jobResult.outputsBaseUrl;
				var outputs = jobResult.outputs != null ? jobResult.outputs : [];
				assertTrue(outputs.length == 2);
				var outputUrl1 = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}${outputName1}';
				return RequestPromises.getBuffer(outputUrl1)
					.pipe(function(out1) {
						assertNotNull(out1);
						assertEquals(out1.compare(bytes1), 0);
						var outputUrl2 = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}${outputName2}';
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
			image: 'busybox',
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
							.pipe(function(jobResult) {
								if (jobResult == null) {
									throw 'jobResult should not be null. Check the above section';
								}
								var outputUrl = jobResult.outputsBaseUrl;
								var outputs = jobResult.outputs != null ? jobResult.outputs : [];
								assertTrue(outputs.length == 2);
								var outputUrl1 = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}${outputName1}';
								return RequestPromises.getBuffer(outputUrl1)
									.pipe(function(out1) {
										assertNotNull(out1);
										assertEquals(out1.compare(bytes1), 0);
										var outputUrl2 = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}${outputName2}';
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

	public function new(targetHost :Host)
	{
		super(targetHost);
	}
}