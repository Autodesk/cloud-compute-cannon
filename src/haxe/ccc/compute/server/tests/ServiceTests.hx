package ccc.compute.server.tests;

import haxe.unit.async.PromiseTestRunner;

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
	@rpc({
		alias:'server-tests',
		doc:'Run all server functional tests'
	})
	public function runServerTests() :Promise<CompleteTestResult>
	{
		return TestServerAPI.runServerAPITests('localhost:$SERVER_DEFAULT_PORT');
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

	public function new() {}
}