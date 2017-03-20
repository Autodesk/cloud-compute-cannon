package ccc.compute.server.tests;

import ccc.storage.ServiceStorage;
import ccc.compute.server.tests.TestCompute.*;

import haxe.unit.async.PromiseTest;
import haxe.unit.async.PromiseTestRunner;

import minject.Injector;

import promhx.PromiseTools;

using t9.util.ColorTraces;

#if (js && !macro)
	import js.npm.shortid.ShortId;
#end

@:enum
abstract DevTest(String) {
	var LongJob = 'longjob';
}

/**
 * Run tests via RPC or curl/HTTP.
 */
class ServiceTests
{
	@inject
	public var _injector :Injector;
	@inject
	public var _context :t9.remoting.jsonrpc.Context;

	var targetHost :Host = 'localhost:$SERVER_DEFAULT_PORT';

	@post
	public function postInject()
	{
		_context.registerService(this);
	}

	@rpc({
		alias:'server-tests',
		doc:'Run all server functional tests'
	})
	public function runServerTests(?core :Bool = false, ?all :Bool = false, ?jobs :Bool = false, ?worker :Bool = false, ?storage :Bool = false, ?compute :Bool = false, ?dockervolumes :Bool = false, ?distributedtasks :Bool = false, ?failures :Bool = false, ?turbojobs :Bool = false, ?workflows :Bool = false) :Promise<CompleteTestResult>
	{
		if (!(core || all || worker || storage || compute || dockervolumes || jobs || distributedtasks || failures || turbojobs || workflows)) {
			compute = true;
		}
		if (all) {
			core = true;
			worker = true;
			storage = true;
			compute = true;
			dockervolumes = true;
			jobs = true;
			distributedtasks = true;
			failures = true;
			turbojobs = true;
			workflows = true;
		}
		var logString :haxe.DynamicAccess<Bool> = {
			all: all,
			core: core,
			worker: worker,
			storage: storage,
			compute: compute,
			dockervolumes: dockervolumes,
			jobs: jobs,
			distributedtasks: distributedtasks,
			failures: failures,
			turbojobs: turbojobs,
			workflows: workflows
		};
		if (Logger.GLOBAL_LOG_LEVEL <= 30) {
			trace('Running tests: [' + logString.keys().map(function(k) return logString[k] ? k.green() : k.red()).array().join(' ') + ']');
		}

		var runner = new PromiseTestRunner();

		function addTestClass (cls :Class<Dynamic>) {
			var testCollection :haxe.unit.async.PromiseTest = Type.createInstance(cls, []);
			_injector.injectInto(testCollection);
			runner.add(testCollection);
		}

		if (core) {
			addTestClass(TestUnit);
		}

		if (core || jobs) {
			addTestClass(TestJobs);
		}

		if (core || turbojobs) {
			addTestClass(TestTurboJobs);
		}

		if (distributedtasks) {
			addTestClass(ccc.compute.server.util.redis.TestRedisDistributedSetInterval);
		}

		if (core || storage) {
			addTestClass(TestStorageLocal);
			var injectedStorage :ccc.storage.ServiceStorage = _injector.getValue(ccc.storage.ServiceStorage);
			switch(injectedStorage.type) {
				case Sftp: Log.warn('No Test for SFTP storage');
				case Local: //Already running local storage
				case PkgCloud:
					addTestClass(TestStoragePkgCloud);
				case S3:
					addTestClass(TestStorageS3);
			}
		}

		if (dockervolumes || core || storage) {
			addTestClass(ccc.docker.dataxfer.TestDataTransfer);
		}

		// if (worker) {
		// 	var testWorkers = new TestWorkerMonitoring();
		// 	_injector.injectInto(testWorkers);
		// 	runner.add(testWorkers);
		// }

		if (compute || core) {
			addTestClass(TestCompute);
		}

		if (failures) {
			addTestClass(TestFailureConditions);
		}

		if (workflows) {
			addTestClass(ccc.compute.server.cwl.TestCWLApi);
		}

		var exitOnFinish = false;
		var disableTrace = true;
		return runner.run(exitOnFinish, disableTrace)
			.then(function(result) {
				result.tests.iter(function(test) {
					if (test.error != null) {
						trace(test.error.replace('\\n', '\n').red());
					}
				});
				return result;
			});
	}

	@rpc({
		alias:'test-single-job'
	})
	public function testSingleJob() :Promise<Bool>
	{
		var test = new TestCompute();
		_injector.injectInto(test);
		return test.testCompleteComputeJobDirect();
	}

	@rpc({
		alias:'create-test-jobs'
	})
	public function createTestJobs(count :Int, duration :Int) :Promise<Dynamic>
	{
		function createAndSubmitJob() {
			var jobRequest = ServerTestTools.createTestJobAndExpectedResults('createTestJobs', duration);
			return ccc.compute.client.js.ClientJSTools.postJob('http://localhost:9000${SERVER_RPC_URL}', jobRequest.request, {});
		}
		for (i in 0...count) {
			createAndSubmitJob()
				.catchError(function(err) {
					Log.error({error:err, message: 'Error in createTestJobs'});
				});
		}

		return Promise.promise(true);
	}

	@rpc({
		alias:'test-storage',
		doc:'Test the storage service (local, S3, etc)'
	})
	public function runStorageTest() :Promise<ServiceStorageTestResult>
	{
		var injectedStorage :ccc.storage.ServiceStorage = _injector.getValue(ccc.storage.ServiceStorage);
		return injectedStorage.test();
	}

	@rpc({
		alias:'test-compute',
		doc:'Test compute service by running a job that performs all basics: read input, write output, read external output, stdout, and stderr'
	})
	public function runComputeTest() :Promise<ServiceStorageTestResult>
	{
		var injectedStorage :ccc.storage.ServiceStorage = _injector.getValue(ccc.storage.ServiceStorage);
		return injectedStorage.test();
	}

	@rpc({
		alias:'test-rpc',
		doc:'Test function for verifying JSON-RPC calls',
		args:{
			echo: {doc:'String argument will be echoed back'}
		}
	})
	public function test(?echo :String = 'defaultECHO' ) :Promise<String>
	{
		return Promise.promise(echo + echo);
	}

	@rpc({
		alias:'stats-minimal-job',
		doc:'Get the stats when running a minmal job (simple inputs and outputs)'
	})
	public function statsMinimalJob() :Promise<Dynamic>
	{
		var TESTNAME = 'statsMinimalJob';

		var inputValueInline = 'in${ShortId.generate()}';
		var inputName2 = 'in${ShortId.generate()}';

		var outputName1 = 'out${ShortId.generate()}';
		var outputName2 = 'out${ShortId.generate()}';

		var outputValue1 = 'out${ShortId.generate()}';

		var inputInline :ComputeInputSource = {
			type: InputSource.InputInline,
			value: inputValueInline,
			name: inputName2
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

		var inputsArray = [inputInline, inputScript];

		var request: BasicBatchProcessRequest = {
			inputs: inputsArray,
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'],
			resultsPath: customResultsPath,
			inputsPath: customInputsPath,
			outputsPath: customOutputsPath,
			wait: true
		}

		var forms :DynamicAccess<Dynamic> = {};

		return ccc.compute.client.js.ClientJSTools.postJob('http://localhost:9000${SERVER_RPC_URL}', request, forms)
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var redis :js.npm.RedisClient = _injector.getValue(js.npm.RedisClient);
				var jobStats :JobStats = redis;
				return jobStats.getPretty(jobResult.jobId);
			});
	}

	public function new() {}
}