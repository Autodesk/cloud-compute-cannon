package ccc.compute.workers;

/**
 * Manages a pool of workers. Creates Worker objects
 * as needed to monitor individual worker instances.
 *
 * Does not control the the instantiation or
 * removal of workers.
 */
import util.DockerTools;

import js.Node;
import js.npm.RedisClient;
import js.npm.ssh2.Ssh;
import js.npm.docker.Docker;

import promhx.Promise;
import promhx.PublicStream;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.deferred.DeferredStream;
import promhx.CallbackPromise;

import util.RedisTools;

class WorkerManager
{
	@inject public var _injector :minject.Injector;
	@inject public var _redis :RedisClient;

	var _workerUpdateStream :Stream<String>;
	var _workers = new Map<MachineId, Worker>();
	var _promiseQueue = new promhx.PromiseQueue();
	var log :AbstractLogger;

	/* There can only be one per process */
	static var CURRENT_WORKER_MANAGER :WorkerManager;

	public function new()
	{
		Assert.that(CURRENT_WORKER_MANAGER == null);
		CURRENT_WORKER_MANAGER = this;
	}

	@post public function postInject()
	{
		_workerUpdateStream = RedisTools.createStream(_redis, InstancePool.REDIS_CHANNEL_KEY_WORKERS_UPDATE);
		_workerUpdateStream.then(function(_) {
			syncWorkers();
		});
		syncWorkers();
	}

	public function getWorker(id :MachineId) :Worker
	{
		return _workers.get(id);
	}

	public function getWorkers(?statuses :Array<MachineStatus>) :Array<Worker>
	{
		var arr = [];
		for (w in _workers) {
			if (statuses == null || statuses.has(w.computeStatus)) {
				arr.push(w);
			}
		}
		return arr;
	}

	public function getActiveWorkers() :Array<Worker>
	{
		return getWorkers([MachineStatus.Available, MachineStatus.WaitingForRemoval, MachineStatus.Removing]);
	}

	/**
	 * This is currently only used to prevent tests from conflicting,
	 * since in production there should not be a reason to remove
	 * an entire compute pool provider.
	 * @return [description]
	 */
	public function dispose() :Promise<Bool>
	{
		var promises = [];
		if (_workers != null) {
			for (w in _workers) {
				promises.push(w.dispose());
			}
		}
		_workers = null;
		if (_workerUpdateStream != null) {
			_workerUpdateStream.end();
			_workerUpdateStream = null;
		}
		if (_promiseQueue != null) {
			_promiseQueue.dispose();
			_promiseQueue = null;
		}
		CURRENT_WORKER_MANAGER = null;
		return Promise.whenAll(promises)
			.thenTrue();
	}

	function syncWorkers()
	{
		_promiseQueue.enqueue(function() return __syncWorkers());
	}

	function createWorker(workerDef :WorkerDefinition) :Worker
	{
		return new Worker(workerDef);
	}

	function __syncWorkers() :Promise<Bool>
	{
		var promise = InstancePool.getAllWorkerIds(_redis)
			.pipe(function(workerIds :Array<MachineId>) {
				if (_workers == null) {
					return Promise.promise([]);
				}
				var promises = [];
				for (id in workerIds) {
					if (!_workers.exists(id)) {
						promises.push(InstancePool.getWorker(_redis, id)
							.then(function(workerDef) {
								if (workerDef == null) {
									Log.warn('InstancePool.getWorker(id=$id) workerDef result==null workers(redis)=$workerIds workers(here)=${_workers.keys()}');
									return;
								}
								if (_workers == null) {
									return;
								}
								if (!_workers.exists(id)) {
									var worker = createWorker(workerDef);
									_workers.set(workerDef.id, worker);
									_injector.injectInto(worker);
									Log.debug('Creating a new worker id=${workerDef.id} total=${getWorkers().length}');
								}
							}));
					}
				}

				var targetSet = Set.createString(workerIds);
				for (id in _workers.keys()) {
					if (!targetSet.has(id)) {
						var workerToRemove = _workers.get(id);
						_workers.remove(id);
						Log.debug('Removing worker id=${workerToRemove.id} total=${getWorkers().length}');
						workerToRemove.dispose();
					}
				}
				return Promise.whenAll(promises);
			})
			.then(function(_) {
				return true;
			});
		return promise;
	}

#if debug
	public function whenFinishedCurrentChanges() :Promise<Bool>
	{
		return _promiseQueue.whenEmpty();
	}
#end
}