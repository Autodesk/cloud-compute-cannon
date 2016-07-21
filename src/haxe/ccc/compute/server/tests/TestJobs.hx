package ccc.compute.server.tests;

import haxe.io.*;

import js.node.Buffer;

import util.DockerRegistryTools;

import promhx.RequestPromises;

class TestJobs extends ServerAPITestBase
{
	@timeout(120000)
	public function testWriteStdoutAndStderr() :Promise<Bool>
	{
		var outputValueStdout = 'out${Std.int(Math.random() * 100000000)}';
		var outputValueStderr = 'out${Std.int(Math.random() * 100000000)}';
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
		return proxy.submitJob('busybox', ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input])
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
		return proxy.submitJob('busybox', ["cat", '/$DIRECTORY_INPUTS/$inputName'], [input])
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
						stdout = stdout != null ? stdout.trim() : stdout;
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
		return proxy.submitJob('busybox', ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input])
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
		var bytes1 = new Buffer([31, 33, 73]);
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

		//A scrit that copies the inputs to outputs
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
		return proxy.submitJob('busybox', ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [inputScript, inputBinaryValue1, inputBinaryValue2])
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

	public function new(targetHost :Host)
	{
		super(targetHost);
	}
}