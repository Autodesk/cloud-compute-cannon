package ccc.compute.server.tests;

import ccc.storage.ServiceStorage;

import haxe.unit.async.PromiseTest;
import haxe.unit.async.PromiseTestRunner;

import minject.Injector;

import promhx.PromiseTools;

using t9.util.ColorTraces;

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

	@rpc({
		alias:'server-tests',
		doc:'Run all server functional tests'
	})
	public function runServerTests(?core :Bool = false, ?all :Bool = false, ?jobs :Bool = false, ?registry :Bool = false, ?worker :Bool = false, ?storage :Bool = false, ?compute :Bool = false, ?dockervolumes :Bool = false) :Promise<CompleteTestResult>
	{
		if (!(core || all || registry || worker || storage || compute || dockervolumes || jobs)) {
			compute = true;
		}
		if (all) {
			core = true;
			registry = true;
			worker = true;
			storage = true;
			compute = true;
			dockervolumes = true;
			jobs = true;
		}
		var logString :haxe.DynamicAccess<Bool> = {
			all: all,
			core: core,
			registry: registry,
			worker: worker,
			storage: storage,
			compute: compute,
			dockervolumes: dockervolumes,
			jobs: jobs
		};
		trace('Running tests: [' + logString.keys().map(function(k) return logString[k] ? k.green() : k.red()).array().join(' ') + ']');

		var targetHost :Host = 'localhost:$SERVER_DEFAULT_PORT';
		var runner = new PromiseTestRunner();

		if (core) {
			runner.add(new TestUnit());
		}

		if (core || jobs) {
			runner.add(new TestJobs(targetHost));
		}

		if (core || storage) {
			runner.add(new TestStorageLocal(ccc.storage.ServiceStorageLocalFileSystem.getService()));
			var injectedStorage :ccc.storage.ServiceStorage = _injector.getValue(ccc.storage.ServiceStorage);
			switch(injectedStorage.type) {
				case Sftp: Log.warn('No Test for SFTP storage');
				case Local: //Already running local storage
				case PkgCloud:
					var test :PromiseTest = new TestStoragePkgCloud(cast injectedStorage);
					runner.add(test);
				case S3:
					var test :PromiseTest = new TestStorageS3(cast  injectedStorage);
					runner.add(test);
			}
		}

		if (dockervolumes || core || storage) {
			runner.add(new ccc.docker.dataxfer.TestDataTransfer());
		}

		if (registry) {
			runner.add(new TestRegistry(targetHost));
		}

		if (worker) {
			var testWorkers = new TestWorkerMonitoring();
			_injector.injectInto(testWorkers);
			runner.add(testWorkers);
		}

		if (compute || core) {
			runner.add(new TestCompute(targetHost));
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
		alias:'test-jobs',
		doc:'Various helpers for testing by running specific jobs'
	})
	public function devTestTools(test :DevTest, ?count :Int = 1, ?sleeptime :Int = 30) :Promise<Dynamic>
	{
		trace('devTestTools test=$devTestTools count=$devTestTools');
		if (count < 0) {
			return PromiseTools.error('count must be >- 0');
		}
		var rpcUrl = 'http://localhost:${SERVER_DEFAULT_PORT}${SERVER_RPC_URL}';
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.ServiceBatchCompute, true)
			.setConnection(new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(rpcUrl));
		return Promise.promise(true)
			.pipe(function(_) {
				var promises = [];
				for (i in 0...count) {
					promises.push(proxy.submitJob(DOCKER_IMAGE_DEFAULT, ['sleep', '$sleeptime']));
				}
				return Promise.whenAll(promises);
			})
			.then(function(results) {
				trace('results=${results}');
				return results;
			});
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

	public function new() {}
}