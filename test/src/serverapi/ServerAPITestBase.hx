package compute;

import js.npm.RedisClient;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

import ccc.compute.InitConfigTools;
import ccc.compute.execution.Jobs;
import ccc.compute.ConnectionToolsRedis;
import ccc.compute.workers.WorkerManager;
import ccc.compute.workers.WorkerProviderBase;
import ccc.storage.*;

using Lambda;
using promhx.PromiseTools;

typedef Disposable = {
	function dispose() :Promise<Bool>;
}

class TestServerAPIBase extends TestBase
{
	public static function resetRemoteServer(host :Host) :Promise<Bool>
	{
		var serverHost
	}

	public static function getProxy(rpcUrl :UrlString)
	{
		return ccc.compute.cli.CliTools.getProxy(rpcUrl);
	}

	var _redis :RedisClient;
	var _serverHost :Host;

	override public function setup() :Null<Promise<Bool>>
	{
		var env = Node.process.env;
		if (!Reflect.hasField(env, ENV_VAR_CCC_ADDRESS)) {
			throw 'Missing env var $ENV_VAR_CCC_ADDRESS';
		}
		_serverHost = 
		return super.setup()
			.pipe(function(_) {

			});
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {

			});
	}


}