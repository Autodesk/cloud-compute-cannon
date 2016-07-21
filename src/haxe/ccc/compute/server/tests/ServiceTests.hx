package ccc.compute.server.tests;

import haxe.unit.async.PromiseTest;
import haxe.unit.async.PromiseTestRunner;
import minject.Injector;
import promhx.PromiseTools;

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
	public function runServerTests() :Promise<CompleteTestResult>
	{
		var targetHost :Host = 'localhost:$SERVER_DEFAULT_PORT';
		var runner = new PromiseTestRunner();

		// runner.add(new TestUnit());
		// runner.add(new TestStorageLocal(ccc.storage.ServiceStorageLocalFileSystem.getService()));
		// var injectedStorage :ccc.storage.ServiceStorage = _injector.getValue(ccc.storage.ServiceStorage);
		// switch(injectedStorage.type) {
		// 	case Sftp: Log.warn('No Test for SFTP storage');
		// 	case Local: //Already running local storage
		// 	case Cloud:
		// 		var test :PromiseTest = new TestStorageS3(cast injectedStorage);
		// 		runner.add(test);
		// }

		runner.add(new TestJobs(targetHost));
		// runner.add(new TestRegistry(targetHost));

		var exitOnFinish = false;
		var disableTrace = true;
		return runner.run(exitOnFinish, disableTrace)
			.then(function(result) {
				result.tests.iter(function(test) {
					if (test.error != null) {
						traceRed(test.error.replace('\\n', '\n'));
					}
				});
				return result;
			});
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