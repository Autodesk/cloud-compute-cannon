package ccc.compute.server.tests;

import js.Node;
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

class ServerAPITestBase extends haxe.unit.async.PromiseTest
{
	var _redis :RedisClient;
	var _serverHost :Host;
	var _serverHostRPCAPI :UrlString;

	override public function setup() :Null<Promise<Bool>>
	{
		_serverHost = ServerTestTools.getServerAddress();
		_serverHostRPCAPI = 'http://${_serverHost}${SERVER_RPC_URL}';
		return super.setup()
			.pipe(function(_) {
				return ServerTestTools.resetRemoteServer(_serverHost);
			});
	}
}