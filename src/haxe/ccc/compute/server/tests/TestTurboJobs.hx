package ccc.compute.server.tests;

import ccc.compute.client.js.ClientJSTools;

import haxe.DynamicAccess;
import haxe.io.*;

import haxe.remoting.JsonRpc;

import js.npm.shortid.ShortId;

import promhx.StreamPromises;
import promhx.RequestPromises;
import promhx.deferred.DeferredPromise;

class TestTurboJobs extends ServerAPITestBase
{
	public static var TEST_BASE = 'tests';
	@inject public var _fs :ServiceStorage;
	@inject public var routes :ccc.compute.server.execution.routes.RpcRoutes;
	@inject public var _redis :RedisClient;

	@timeout(240000)
	public function testTurboJobComplete() :Promise<Bool>
	{
		var TESTNAME = 'testTurboJobComplete';

		var random = ShortId.generate();

		var customInputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_INPUTS';
		var customOutputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_OUTPUTS';
		var customResultsPath = '$TEST_BASE/$TESTNAME/$random/results';

		var inputs :DynamicAccess<String> = {};

		var inputName2 = 'in${ShortId.generate()}';
		var inputName3 = 'in${ShortId.generate()}';
		inputs[inputName2] = 'in${ShortId.generate()}';
		inputs[inputName3] = 'in${ShortId.generate()}';

		var outputName1 = 'out${ShortId.generate()}';
		var outputName2 = 'out${ShortId.generate()}';
		var outputName3 = 'out${ShortId.generate()}';

		var outputValue1 = 'out${ShortId.generate()}';

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
mkdir -p /$DIRECTORY_OUTPUTS
echo "$outputValue1" > /$DIRECTORY_OUTPUTS/$outputName1
cat /$DIRECTORY_INPUTS/$inputName2 > /$DIRECTORY_OUTPUTS/$outputName2
cat /$DIRECTORY_INPUTS/$inputName3 > /$DIRECTORY_OUTPUTS/$outputName3
';
		var targetStdout = '$outputValueStdout\n$outputValueStdout\nfoo\n$outputValueStdout'.trim();
		var targetStderr = '$outputValueStderr';
		var scriptName = 'script.sh';
		inputs[scriptName] = script;

		var random = ShortId.generate();

		var request: BatchProcessRequestTurbo = {
			inputs: inputs,
			image: DOCKER_IMAGE_DEFAULT,
			command: ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'],
			parameters: {maxDuration:30, cpus:1}
		}

		var proxy = ServerTestTools.getProxy();
		return proxy.submitTurboJobJson(request)
			.then(function(jobResult :JobResultsTurbo) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				assertNotNull(jobResult.outputs);
				assertNotNull(jobResult.outputs[outputName1]);
				assertNotNull(jobResult.outputs[outputName2]);
				assertNotNull(jobResult.outputs[outputName3]);
				assertEquals(jobResult.outputs[outputName1].trim(), outputValue1);
				assertEquals(jobResult.outputs[outputName2].trim(), inputs[inputName2]);
				assertEquals(jobResult.outputs[outputName3].trim(), inputs[inputName3]);

				assertEquals(jobResult.stderr[0].trim(), outputValueStderr);
				assertEquals(jobResult.stdout[0].trim(), outputValueStdout);

				return true;
			});
	}

	@timeout(240000)
	public function testTurboJobInAndOutOfRedis() :Promise<Bool>
	{
		var TESTNAME = 'testTurboJobInAndOutOfRedis';

		var random = ShortId.generate();

		var customInputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_INPUTS';
		var customOutputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_OUTPUTS';
		var customResultsPath = '$TEST_BASE/$TESTNAME/$random/results';

		var inputs :DynamicAccess<String> = {};

		var inputName2 = 'in${ShortId.generate()}';
		var inputName3 = 'in${ShortId.generate()}';
		inputs[inputName2] = 'in${ShortId.generate()}';
		inputs[inputName3] = 'in${ShortId.generate()}';

		var outputName1 = 'out${ShortId.generate()}';
		var outputName2 = 'out${ShortId.generate()}';
		var outputName3 = 'out${ShortId.generate()}';

		var outputValue1 = 'out${ShortId.generate()}';

		var outputValueStdout = 'out${ShortId.generate()}';
		var outputValueStderr = 'out${ShortId.generate()}';
		//Multiline stdout
		var script =
'#!/bin/sh
sleep 2
echo "$outputValueStdout"
echo "$outputValueStdout"
echo foo
echo "$outputValueStdout"
echo "$outputValueStderr" >> /dev/stderr
mkdir -p /$DIRECTORY_OUTPUTS
echo "$outputValue1" > /$DIRECTORY_OUTPUTS/$outputName1
cat /$DIRECTORY_INPUTS/$inputName2 > /$DIRECTORY_OUTPUTS/$outputName2
cat /$DIRECTORY_INPUTS/$inputName3 > /$DIRECTORY_OUTPUTS/$outputName3
';
		var targetStdout = '$outputValueStdout\n$outputValueStdout\nfoo\n$outputValueStdout'.trim();
		var targetStderr = '$outputValueStderr';
		var scriptName = 'script.sh';
		inputs[scriptName] = script;

		var random = ShortId.generate();

		var jobId :JobId = ShortId.generate();

		var request: BatchProcessRequestTurbo = {
			id: jobId,
			inputs: inputs,
			image: DOCKER_IMAGE_DEFAULT,
			command: ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'],
			parameters: {maxDuration:10, cpus:1}
		}

		var proxy = ServerTestTools.getProxy();

		var activeSubmissionPromise = proxy.submitTurboJobJson(request);

		return PromiseTools.delay(100)
			.pipe(function(_) {
				var turboJobs :TurboJobs = _redis;
				return turboJobs.isJob(jobId)
					.then(function(isJob) {
						assertTrue(isJob);
						return true;
					});
			})
			.pipe(function(_) {
				return activeSubmissionPromise;
			})
			.then(function(jobResult :JobResultsTurbo) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				assertNotNull(jobResult.outputs);
				assertNotNull(jobResult.outputs[outputName1]);
				assertNotNull(jobResult.outputs[outputName2]);
				assertNotNull(jobResult.outputs[outputName3]);
				assertEquals(jobResult.outputs[outputName1].trim(), outputValue1);
				assertEquals(jobResult.outputs[outputName2].trim(), inputs[inputName2]);
				assertEquals(jobResult.outputs[outputName3].trim(), inputs[inputName3]);

				assertEquals(jobResult.stderr[0].trim(), outputValueStderr);
				assertEquals(jobResult.stdout[0].trim(), outputValueStdout);

				return true;
			})
			.pipe(function(_) {
				var turboJobs :TurboJobs = _redis;
				return turboJobs.isJob(jobId)
					.then(function(isJob) {
						assertFalse(isJob);
						return true;
					});
			});
	}

	public function new() { super(); }
}