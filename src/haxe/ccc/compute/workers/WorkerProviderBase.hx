package ccc.compute.workers;

import haxe.Json;

import js.Node;
import js.npm.RedisClient;

import ccc.compute.InstancePool;

import promhx.Promise;
import promhx.Promise;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.CallbackPromise;

import t9.abstracts.net.*;
import t9.abstracts.time.*;

import util.RedisTools;
import util.CliColors;

using promhx.PromiseTools;
using Lambda;

//This blob is recorded when you want to actually delay
//the shutdown of machines due to the efficiency of
//billing cycles.
typedef MachineRemovalDelayed = {
	var id :MachineId;
	var timeoutId :Dynamic;
	var removalTime :TimeStamp;
	@:optional var meta :Dynamic;
}

class WorkerProviderBase
	implements WorkerProvider
{
	public var id (default, null) :String;
	public var redis (get, null) :RedisClient;
	public var ready (get, null) :Promise<Bool>;
	public var log :AbstractLogger;

	@inject public var _redis :RedisClient;
	#if debug public #end
	var _config :ProviderConfigBase;
	var _streamMachineCount :Stream<TargetMachineCount>;
	var _streamMachineStatus :Stream<Array<StatusResult>>;
	var _ready :Promise<Bool> = Promise.promise(true);
	var _targetWorkerCount :WorkerCount = 0;
	var _actualWorkerCount :WorkerCount = 0;
	var _promiseQueue :promhx.PromiseQueue = new promhx.PromiseQueue();
	var _updateCountPromise :Promise<Int>;
	var _disposed :Bool = false;

	//For machines that are not shut down immediately.
	var _deferredRemovals :Array<MachineRemovalDelayed> = [];

	public function new(config :ServiceConfigurationWorkerProvider)
	{
		_config = config;
		log = Logger.child({'WorkerProvider':config.type});
		_test = TEST++;
	}

	@post
	public function postInjection() :Promise<Bool>
	{
		log.debug({f:'postInjection'});
		Assert.that(_streamMachineCount == null, Type.getClassName(Type.getClass(this)) + ' has already been injected');
		if (id == null) {
			throw 'Must set id before calling super constructor';
		}

		_ready = Promise.promise(true)
			.pipe(function(_) {
				log.debug({f:'postInjection', log:'InstancePool.getAllWorkerTimeouts'});
				return InstancePool.getAllWorkerTimeouts(redis, id)
					.then(function(deferredWorkers) {
						if (deferredWorkers != null) {
							for (deferredWorker in deferredWorkers) {
								// Log.info('Added deferred worker on init=$deferredWorker');
								addWorkerToDeferred(deferredWorker.id, deferredWorker.time);
							}
						}
						return true;
					});
			})
			.pipe(function(_) {
				log.debug({f:'postInjection', log:'updateConfig'});
				return updateConfig(_config);
			})
			.then(function(_) {
				log.debug({f:'postInjection', log:'RedisTools.createJsonStream'});
				_streamMachineCount = RedisTools.createJsonStream(_redis, InstancePool.REDIS_KEY_WORKER_POOL_TARGET_INSTANCES);
				_streamMachineCount
					.then(function(counts :TargetMachineCount) {
						if (counts != null && Reflect.field(counts, id) != null) {
							var count :Int = Reflect.field(counts, id);
							setWorkerCount(count);
						}
					});
				_streamMachineStatus = RedisTools.createStreamCustom(_redis, InstancePool.REDIS_KEY_WORKER_STATUS_CHANNEL_PREFIX + "*",
					function(_) {
						return InstancePool.getInstancesInPool(_redis, id);
					}, true);
				_streamMachineStatus
					.then(function(results :Array<StatusResult>) {
						onWorkerStatusUpdate(results);
					});
				return true;
			});

		_promiseQueue.enqueue(function() return _ready);
		return _ready;
	}

	public function setMaxWorkerCount(val :WorkerCount) :Promise<Bool>
	{
		return InstancePool.setMaxInstances(_redis, id, val)
			.thenTrue();
	}

	public function setPriority(val :Int) :Promise<Bool>
	{
		return InstancePool.setPoolPriority(_redis, id, val)
			.thenTrue();
	}

	public function setDefaultWorkerParameters(parameters :WorkerParameters) :Promise<Bool>
	{
		return InstancePool.setDefaultWorkerParameters(_redis, id, parameters)
			.thenTrue();
	}

	static var TEST = 1;
	var _test :Int;

	public function setWorkerCount(newCount :Int) :Promise<Bool>
	{
		log.debug({f:'setWorkerCount', newCount:newCount});
		// Log.info('setWorkerCount newCount=$newCount _targetWorkerCount=$_targetWorkerCount _actualWorkerCount=$_actualWorkerCount');
		if (newCount > _config.maxWorkers || newCount < _config.minWorkers) {
			//This can occur if counts are set in between config updates
			// Log.info('   newCount=$newCount not [${_config.minWorkers} - ${_config.maxWorkers}], ignoring.');
			return Promise.promise(true);
		}
		_targetWorkerCount = newCount;
		if (_targetWorkerCount != _actualWorkerCount) {
			if (_updateCountPromise == null) {
				_updateCountPromise = updateWorkerCount(_redis, _targetWorkerCount, this)
					.then(function(currentCount) {
						_updateCountPromise = null;
						_actualWorkerCount = currentCount;
						// Log.info('  setWorkerCount FINISHED _actualWorkerCount=$_actualWorkerCount _targetWorkerCount=$_targetWorkerCount');
						if (_targetWorkerCount != _actualWorkerCount) {
							setWorkerCount(_targetWorkerCount);
						}
						return currentCount;
					});
				_updateCountPromise.catchError(function(err) {
					_updateCountPromise = null;
					// Log.info('  setWorkerCount FINISHED WITH ERR=$err _actualWorkerCount=$_actualWorkerCount _targetWorkerCount=$_targetWorkerCount');
				});
				_promiseQueue.enqueue(function() {
					return _updateCountPromise;
				});
				return _updateCountPromise
					.thenTrue();
			} else {
				// Log.info('    updateWorkerCount is already underway, it will setWorkerCount again when resolved');
				return Promise.promise(true);
			}
		} else {
			// Log.info('    newCount=$newCount == _targetWorkerCount, ignoring.');
			return Promise.promise(true);
		}
	}

	/**
	 * Sets the worker state to 'deferred' and marks it for actual
	 * shutdown after some cloud provider specific delay.
	 * @param  workerId :MachineId    [description]
	 * @return          [description]
	 */
	public function removeWorker(workerId :MachineId) :Promise<Bool>
	{
		log.debug('WorkerProviderBase.removeWorker $workerId');
		return destroyInstance(workerId);
		// return getShutdownDelay(workerId)
		// 	.pipe(function(delay) {
		// 		var removalTimeStamp :TimeStamp = TimeStamp.now().addSeconds(delay.toSeconds());
		// 		// Log.info('removeWorker $workerId delay=${delay.toString()} removalTimeStamp=$removalTimeStamp');
		// 		return InstancePool.setWorkerTimeout(redis, workerId, removalTimeStamp)
		// 			.then(function(_) {
		// 				addWorkerToDeferred(workerId, removalTimeStamp);
		// 				return true;
		// 			});
		// 	});
	}

	public function createWorker() :Promise<WorkerDefinition>
	{
		var workerId = getDeferredWorkerId();
		if (workerId != null) {
			return InstancePool.setWorkerStatus(redis, workerId, MachineStatus.Available)
				.pipe(function(_) {
					return InstancePool.getWorker(redis, workerId);
				});
		} else {
			return null;
		}
	}

	public function createIndependentWorker() :Promise<WorkerDefinition>
	{
		throw 'Not implemented';
		return null;
	}

	public function createServer() :Promise<WorkerDefinition>
	{
		throw 'Not implemented';
		return null;
	}

	public function destroyInstance(instanceId :MachineId) :Promise<Bool>
	{
		removeFromDeferred(instanceId);
		return Promise.promise(true);
	}

	public function shutdownAllWorkers() :Promise<Bool>
	{
		return Promise.promise(true);
	}

	public function dispose() :Promise<Bool>
	{
		if (_disposed) {
			return Promise.promise(true);
		}
		log.debug({'WorkerProviderStatus':'disposing'});
		_disposed = true;
		if (_streamMachineCount != null) {
			_streamMachineCount.end();
			_streamMachineCount = null;
		}
		if (_streamMachineStatus != null) {
			_streamMachineStatus.end();
			_streamMachineStatus = null;
		}
		_config.minWorkers = 0;
		var promise :Promise<Int> = _updateCountPromise != null ? _updateCountPromise : Promise.promise(0);
		return promise
			.pipe(function(_) {
				return updateConfig(_config);
			})
			.pipe(function(_) {
				return InstancePool.toJson(redis)
					.pipe(function(jsondump :InstancePoolJson) {
						var promises = [];
						for(computeJobId in jsondump.getJobsForPool(id).keys()) {
							promises.push(ComputeQueue.removeComputeJob(redis, computeJobId));
						}
						return Promise.whenAll(promises);
					});
			})
			.pipe(function(_) {
				return _updateCountPromise != null ? _updateCountPromise : Promise.promise(0);
				// return _updateCountQueue.whenEmpty();
			})
			.pipe(function(_) {
				return _promiseQueue.whenEmpty();
			});
	}

	function addWorkerToDeferred(workerId :MachineId, removalTimeStamp :TimeStamp)
	{
		removeFromDeferred(workerId);
		var delay :Seconds = removalTimeStamp.subtract(TimeStamp.now());
		if (delay.toFloat() < 0) {
			delay = new Seconds(0.0);
		}
		var delayMs = delay.toMilliseconds().toInt();

		//TODO: There is a bug in the deferred logic. For now:
		// delay = new Minutes(45);
		log.debug('addWorkerToDeferred workerId=$workerId removalTimeStamp=$removalTimeStamp delay=${delay.toMilliseconds().toInt()}');
		var machineRemovalDelayed = {
			id: workerId,
			timeoutId: Node.setTimeout(function() {
				_deferredRemovals = _deferredRemovals.filter(function(e) return e.id != workerId);
				log.debug('Shutdown deferred worker=$workerId delayMs=${delay} removalTimeStamp=${removalTimeStamp.toString()} now=${Date.now().toString()}');
				InstancePool.setWorkerDeferredToRemoving(_redis, workerId);
			}, delayMs),
			removalTime: removalTimeStamp
		}
		// log.info('worker deferring for removal machine=$workerId removalTimeStamp=${removalTimeStamp.toString()} delay=${delay} now=${Date.now().toString()}');
		_deferredRemovals.push(machineRemovalDelayed);
		_deferredRemovals.sort(function(e1, e2) {
			return e1.removalTime < e2.removalTime ? 1 : (e1.removalTime == e2.removalTime ? 0 : -1);
		});
	}

	function removeFromDeferred(workerId :MachineId)
	{
		_deferredRemovals = _deferredRemovals.filter(function(e) {
			if (e.id != workerId) {
				return true;
			} else {
				Node.clearTimeout(e.timeoutId);
				return false;
			}
		});
	}

	/**
	 * Different providers have different billing cycles
	 * and billing increments.
	 * @param  workerId :MachineId    [description]
	 * @return          The time to shutdown the machine, if not needed.
	 */
	function getShutdownDelay(workerId :MachineId) :Promise<Minutes>
	{
		return Promise.promise(_config.billingIncrement);
	}

	var _instanceStatusCache = new Map<MachineId,MachineStatus>();
	function onWorkerStatusUpdate(statuses :Array<StatusResult>)
	{
		log.debug({statuses:statuses, f:'onWorkerStatusUpdate'});
		for (status in statuses) {
			var instanceId = status.id;
			if (_instanceStatusCache.get(instanceId) == status.status) {
				continue;
			} else {
				_instanceStatusCache.set(instanceId, status.status);
			}

			switch(status.status) {
				case Removing:
					log.trace('WorkerProviderBase.removeWorker ${instanceId}');
					removeWorker(status.id)
						.errorPipe(function(err) {
							log.trace('its ok to have this error after removing a worker');
							return Promise.promise(true);
						})
						.pipe(function(_) {
							return InstancePool.removeInstance(_redis, instanceId)
								.pipe(function(_) {
									_instanceStatusCache.remove(instanceId);
									_actualWorkerCount--;
									return InstancePool.getTargetWorkerCount(redis, id)
										.pipe(function(targetCount) {
											log.debug({log:'worker removed, setting targetcount=$targetCount _actualWorkerCount=$_actualWorkerCount'});
											return setWorkerCount(targetCount);
										});
								});
						});
				case Deferred:
					log.debug('instance=$instanceId deferred');
					getShutdownDelay(instanceId)
						.pipe(function(delay) {
							log.debug('instance=$instanceId TimeStamp.now()=${TimeStamp.now()} delay=${delay} delay.toSeconds()=${delay.toSeconds()}');
							var removalTimeStamp :TimeStamp = TimeStamp.now().addSeconds(delay.toSeconds());
							log.debug('instance=$instanceId deferred removalTimeStamp=$removalTimeStamp');
							return InstancePool.setWorkerTimeout(redis, instanceId, removalTimeStamp)
								.then(function(_) {
									addWorkerToDeferred(instanceId, removalTimeStamp);
									return true;
								});
						});
				default://Nothing
			}
		}
	}

	function addRunningPromiseToQueue(promise :Promise<Dynamic>)
	{
		_promiseQueue.enqueue(function() {
			if (promise.isResolved()) {
				return Promise.promise(true);
			} else {
				var deferred = new DeferredPromise();
				promise
					.then(function(_) {
						deferred.resolve(true);
					});
				promise.catchError(function(err) {
					log.error(err);
					deferred.resolve(false);
				});
				return deferred.boundPromise;
			}
		});
	}

	public function updateConfig(config :ProviderConfigBase) :Promise<Bool>
	{
		Assert.notNull(config);
		Assert.notNull(config.maxWorkers);
		Assert.notNull(config.minWorkers);
		Assert.notNull(config.priority);
		if (config.billingIncrement == null) {
			config.billingIncrement = new Minutes(0);
		}
		if (_config == null) {
			_config = config;
		} else {
			_config.maxWorkers = config.maxWorkers;
			_config.minWorkers = config.minWorkers;
			_config.priority = config.priority;
			_config.billingIncrement = config.billingIncrement;
		}

		// Log.info('Initializing provider=$id priority=${_config.priority} minWorkerCount=${_config.minWorkers} maxWorkerCount=${_config.maxWorkers} billingIncrement=${_config.billingIncrement}');
		var promise = InstancePool.registerComputePool(_redis, id, _config.priority, _config.maxWorkers, _config.minWorkers, _config.billingIncrement)
			.thenTrue();
		return promise;
	}

	public function getNetworkHost() :Promise<Host>
	{
		return Promise.promise(new Host(new HostName('localhost')));
	}

	/**
	 * If we have worker machines that have been marked for shutdown, but
	 * are kept around because the billing cycle means that it doesn't make
	 * sense to terminate them immediately, then preferentially use those
	 * waiting machines rather than spend time and $$ to boot up a brand
	 * new instance.
	 * @return [description]
	 */
	function getDeferredWorkerId() :MachineId
	{
		var blob = _deferredRemovals.pop();
		if (blob != null) {
			js.Node.clearTimeout(blob.timeoutId);
		}
		return blob != null ? blob.id : null;
	}

	/** Actually shutdown the worker, e.g. call the AWS API to terminate an instance */
	function shutdownWorker(workerId :MachineId) :Promise<Bool>
	{
		// Log.warn('shutdownWorker not implemented workerId=$workerId');
		return Promise.promise(false);
	}

	#if debug public #end
	function verifyWorkerExists(workerId :MachineId) :Promise<Bool>
	{
		// Log.warn('verifyWorkerExists not implemented workerId=$workerId');
		return Promise.promise(false);
	}

	inline function get_redis() :RedisClient
	{
		return _redis;
	}

	inline function get_ready() :Promise<Bool>
	{
		return _ready;
	}

#if debug
	public function getTargetWorkerCount() :Int
	{
		return _targetWorkerCount;
	}

	public function whenFinishedCurrentChanges() :Promise<Bool>
	{
		return _promiseQueue.whenEmpty();
	}

	public function getDeferredWorkerIds() :Array<MachineId>
	{
		return _deferredRemovals.map(function(m) return m.id);
	}

	/**
	 * When testing we need to create a checkpoint for
	 * updates rather than guessing the time when events
	 * are resolved.
	 */
	public function onceOnCountEquals(val :Int)
	{
		var promise = new DeferredPromise();
		var createdPromise :Stream<Void> = null;
		createdPromise = _streamMachineCount.then(function(counts :TargetMachineCount) {
			if (counts != null && Reflect.field(counts, id) != null) {
				var count :Int = Reflect.field(counts, id);
				if (count == val) {
					_streamMachineCount.unlink(createdPromise);
					if (!promise.isResolved()) {
						promise.resolve(true);
					}
				}
			}
		});
		return promise.boundPromise
			.pipe(function(_) {
				return whenFinishedCurrentChanges();
			});
	}
#end

	static function updateWorkerCount(redis :RedisClient, newWorkerCount :Int, provider :WorkerProvider) :Promise<Int>
	{
		var log = provider.log;
		log.debug('updateWorkerCount newWorkerCount=$newWorkerCount');
		//First get relevant info
		return Promise.promise(true)
			.pipe(function(_) {
				return InstancePool.getInstancesInPool(redis, provider.id);
			})
			.pipe(function(statuses :Array<StatusResult>) {
				//Then take action
				var promises = new Array<Promise<Dynamic>>();
				var readyMachines = statuses.filter(InstancePool.isAvailable);
				//Add new machines?
				if (newWorkerCount > readyMachines.length) {
					var numNewMachines = newWorkerCount - readyMachines.length;
					//First just change idle machines instead of spinning up new ones
					var deferredMachines = statuses.filter(InstancePool.isStatus([MachineStatus.WaitingForRemoval]));
					while(numNewMachines > 0 && deferredMachines.length > 0) {
						var machineId = deferredMachines.pop().id;
						//Is it really idle? What if it had jobs but was waiting to be shut down?
						log.debug('updateWorkerCount adding machine by setting status WaitingForRemoval=>Available worker=$machineId');
						promises.push(InstancePool.setWorkerStatus(redis, machineId, MachineStatus.Available));
						numNewMachines--;
					}
					while (numNewMachines > 0) {
						log.debug('updateWorkerCount createWorker');
						promises.push(provider.createWorker());
						numNewMachines--;
					}
				} else if (newWorkerCount < readyMachines.length) {
					//Remove machines
					//First mark as ready_for_removal any idle machines
					var removeCount = readyMachines.length - newWorkerCount;
					var idle = statuses.filter(function(s) return s.availableStatus == MachineAvailableStatus.Idle);
					while(removeCount > 0 && idle.length > 0) {
						var machineId = idle.pop().id;
						log.debug('updateWorkerCount remove machine by status Idle=>WaitingForRemoval worker=$machineId');
						promises.push(InstancePool.setWorkerStatus(redis, machineId, MachineStatus.WaitingForRemoval));
						removeCount--;
					}
					//Then any working machines
					var working = statuses.filter(function(s) return s.availableStatus == MachineAvailableStatus.Working);
					while(removeCount > 0 && working.length > 0) {
						var machineId = working.pop().id;
						log.debug('updateWorkerCount remove machine by status Working=>WaitingForRemoval worker=$machineId');
						promises.push(InstancePool.setWorkerStatus(redis, machineId, MachineStatus.WaitingForRemoval));
						removeCount--;
					}
					//Then finally max capacity machines
					var maxCapacity = statuses.filter(function(s) return s.availableStatus == MachineAvailableStatus.MaxCapacity);
					while(removeCount > 0 && maxCapacity.length > 0) {
						var machineId = maxCapacity.pop().id;
						log.debug('updateWorkerCount remove machine by status Working=>MaxCapacity worker=$machineId');
						promises.push(InstancePool.setWorkerStatus(redis, machineId, MachineStatus.WaitingForRemoval));
						removeCount--;
					}
					//There should be no more machines to remove
					if (removeCount > 0) {
						log.error('removeCount=$removeCount');
					}
					//Get any machines waiting for removal with no jobs, and completely remove them.
				} else {
					//Machine matches, do nothing
				}
				return Promise.whenAll(promises);
			})
			.pipe(function(_) {
				return ComputeQueue.processPending(redis);
			})
			.then(function(_) {
				return newWorkerCount;
			});
	}
}