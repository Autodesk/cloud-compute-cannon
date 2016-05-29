package compute;

import haxe.Json;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.PromiseTools;
import promhx.RedisPromises;

import ccc.compute.client.ClientCompute;
import ccc.compute.ServiceBatchCompute;
import ccc.compute.Definitions;
import ccc.compute.ConnectionToolsRedis;

import utils.TestTools;

import t9.abstracts.net.*;

using promhx.PromiseTools;

class TestRestartAfterCrashBase extends TestBase
{
	var _env :TypedDynamicObject<String, String>;

	public function new() {}

	override public function setup() :Null<Promise<Bool>>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				return ConnectionToolsRedis.getRedisClient();
			})
			.pipe(function(redis) {
				Assert.notNull(redis);
				return js.npm.RedisUtil.deleteAllKeys(redis);
			});
	}

	function baseTestRestartAfterCrash()
	{
		var port = '9003';
		var hostport :Host = 'localhost:$port';

		_env['PORT'] = port;
		var childProcess = null;
		//Start the local server, map the redis config
		function startServer() {
			return TestTools.forkServerCompute(_env)
				.then(function(serverprocess) {
					childProcess = serverprocess;
					return true;
				});
		}

		var jobId = null;

		return Promise.promise(true)
			.pipe(function(_) {
				return startServer();
			})
			//Submit a job
			.pipe(function(_) {
				var jobParams :BasicBatchProcessRequest = {
					image:'busybox',
					cmd: ['sleep', '2'],
					parameters: {cpus:1, maxDuration:60*1000*10}
				};

				//Get the job id
				return ClientCompute.postJob(hostport, jobParams)
					.then(function(result) {
						jobId = result.jobId;
						return true;
					});
			})
			//Kill the server
			.pipe(function(_) {
				return TestTools.killForkedServer(childProcess);
			})
			//Restart the server
			.pipe(function(_) {
				return startServer();
			})
			.thenWait(3000)
			.pipe(function(_) {
				return ClientCompute.pollJobResult(hostport, jobId, 200, 2000)
					.pipe(function(jobResult) {
						return TestTools.killForkedServer(childProcess);
					});
			});
	}
}