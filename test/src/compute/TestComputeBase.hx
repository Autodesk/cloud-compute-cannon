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

class TestComputeBase extends TestBase
{
	var _childProcess :js.node.child_process.ChildProcess;
	var _workerProvider :WorkerProviderBase;
	var _workerManager :WorkerManager;
	var _jobsManager :Jobs;
	var _fs :ServiceStorage;
	var _redis :RedisClient;

	override public function setup() :Null<Promise<Bool>>
	{
		_injector = new minject.Injector();
		_injector.map(minject.Injector).toValue(_injector);
		return Promise.promise(true)
			.pipe(function(_) {
				return ConnectionToolsRedis.getRedisClient()
					.pipe(function(redis) {
						_redis = redis;
						Assert.notNull(redis);
						_injector.map(js.npm.RedisClient).toValue(redis);
						return js.npm.RedisUtil.deleteAllKeys(redis)
							.pipe(function(_) {
								return InitConfigTools.initAll(redis);
							});
					});
			})
			.then(function(_) {
				//Add local storage in case it's needed.
				var config = InitConfigTools.getDefaultConfig();
				var storageConfig = config.server.storage;//StorageTools.getConfigFromServiceConfiguration(config);
				_injector.map('ccc.storage.StorageDefinition').toValue(storageConfig);
				var storage :ServiceStorage = StorageTools.getStorage(storageConfig);
				Assert.notNull(storage);
				_injector.map(ServiceStorage).toValue(storage);
				return true;
			});
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		var localRedis = _redis;
		return super.tearDown()
			.pipe(function(_) {
				var disposable :Array<Disposable> = [_workerProvider, _workerManager, _jobsManager];
				_workerProvider = null;
				_workerManager = null;
				_jobsManager = null;
				_redis = null;
				var promises :Array<Promise<Dynamic>> = disposable.map(function(e) {
					return e == null ? Promise.promise(true) : e.dispose();
				});
				return Promise.whenAll(promises);
			})
			.pipe(function(_) {
				if (_childProcess != null) {
					//Kill the test server
					var promise = new DeferredPromise();
					_childProcess.once('exit', function(e) {
						_childProcess = null;
						promise.resolve(true);
					});
					_childProcess.kill('SIGKILL');
					return promise.boundPromise;
				} else {
					return Promise.promise(true);
				}
			})
			.pipe(function(_) {
				return js.npm.RedisUtil.deleteAllKeys(localRedis);
			})
			.then(function(_) {
				return true;
			});
	}
}