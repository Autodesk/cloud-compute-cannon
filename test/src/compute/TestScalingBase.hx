package compute;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;
import js.npm.FsExtended;
import js.npm.RedisClient;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.PromiseTools;
import promhx.RedisPromises;

import ccc.compute.InstancePool;
import ccc.compute.ComputeTools;
import ccc.compute.ComputeQueue;
import ccc.compute.ConnectionToolsRedis;
import ccc.compute.workers.WorkerManager;
import ccc.compute.workers.WorkerProvider;
import ccc.compute.workers.WorkerProviderBase;
import ccc.compute.workers.VagrantTools;
import ccc.storage.ServiceStorage;
import ccc.storage.ServiceStorageLocalFileSystem;

import utils.TestTools;

import t9.abstracts.time.*;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;
using ccc.compute.InstancePool;
using ccc.compute.workers.WorkerProviderTools;

class TestScalingBase extends TestComputeBase
{
	var _disposers :Array<Void->Void>;

	public function new() {}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.then(function(_) {
				var dateString = TestTools.getDateString();
				var clsName = Type.getClassName(Type.getClass(this));
				clsName = clsName.substr(clsName.lastIndexOf('.') + 1);
				var jobFsPath = 'tmp/$clsName/$dateString';
				_injector.unmap(ServiceStorage);
				_injector.map(ServiceStorage).toValue(new ServiceStorageLocalFileSystem().setRootPath(jobFsPath));
				_disposers = [];
				_workerManager = new WorkerManager();
				_injector.injectInto(_workerManager);
			})
			.thenTrue();
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		if (_disposers != null) {
			for (d in _disposers) {
				d();
			}
			_disposers = null;
		}
		return super.tearDown();
	}

	function baseTestScalingMachines(?machineTargetCount :Int = 2, ?machineTargetMaxCount :Int = 3, ?machineTargetMinCount :Int = 1)
	{
		assertNotNull(_redis);
		_redis.on(RedisEvent.Error, function(err) {
			Log.error('REDIS ERROR=$err');
		});
		var redis = _redis;

		var manager = _workerManager;
		var provider = _workerProvider;
		assertNotNull(provider);

		var priority :WorkerPoolPriority = 1;

		var max = machineTargetMaxCount;
		var min = machineTargetMinCount;
		function check(value :Int, target :Int) :Bool {
			if (target >= max) {
				return value == max;
			} else if (target <= min) {
				return value == min;
			} else {
				return value == target;
			}
		}

		return Promise.promise(true)
			.pipe(function(_) {
				return ComputeQueue.setAutoscaling(redis, false);
			})
			.pipe(function(_) {
				return provider.updateConfig({maxWorkers:machineTargetMaxCount, minWorkers:machineTargetMinCount, priority:priority, billingIncrement:0})
					.pipe(function(_) {
						return InstancePool.toJson(redis);
					})
					.then(function(jsondump :InstancePoolJson) {
						assertEquals(jsondump.getTargetWorkerCount(provider.id), machineTargetMinCount);
						assertEquals(jsondump.getMaxWorkerCount(provider.id), machineTargetMaxCount);
						return true;
					});
			})

			//Add machines, check that they have been added
			.pipe(function(_) {
				return InstancePool.setTotalWorkerCount(redis, machineTargetCount)
					.thenWait(50)
					.pipe(function(_) {
						return InstancePool.toJson(redis)
							// .traceJson()
							.then(function(jsondump :InstancePoolJson) {
								assertEquals(jsondump.getTargetWorkerCount(provider.id), Std.int(Math.min(machineTargetCount, machineTargetMaxCount)));
								assertEquals(jsondump.getMaxWorkerCount(provider.id), machineTargetMaxCount);
								assertEquals(jsondump.getMinWorkerCount(provider.id), machineTargetMinCount);
								return true;
							});
					})
					.pipe(function(_) {
						return provider.whenFinishedCurrentChanges();
					})
					.thenWait(50)
					.pipe(function(_) {
						assertTrue(check(provider.getTargetWorkerCount(), machineTargetCount));
						return provider.whenFinishedCurrentChanges();
					})
					.thenWait(100)
					.then(function(_) {
						return assertTrue(check(provider.getTargetWorkerCount(), machineTargetCount));
					});
			})

			//Add more machines that the pool can handle, it should only add up to its max
			.pipe(function(_) {
				return InstancePool.setTotalWorkerCount(redis, machineTargetMaxCount + 1)
					// .thenWait(50)
					.pipe(function(_) {
						return InstancePool.toJson(redis)
							.then(function(jsondump :InstancePoolJson) {
								assertEquals(jsondump.getTargetWorkerCount(provider.id), machineTargetMaxCount);
								assertEquals(jsondump.getMaxWorkerCount(provider.id), machineTargetMaxCount);
								return true;
							});
					})
					.thenWait(50)
					.pipe(function(_) {
						return provider.whenFinishedCurrentChanges();
					})
					.pipe(function(_) {
						return InstancePool.getInstancesInPool(redis, provider.id)
							.then(function(out) {
								return assertEquals(out.filter(InstancePool.isAvailable).length, machineTargetMaxCount);
							});
					})
					.pipe(function(_) {
						assertEquals(provider.getTargetWorkerCount(), machineTargetMaxCount);
						return provider.whenFinishedCurrentChanges();
					})
					.then(function(_) {
						return assertEquals(provider.getTargetWorkerCount(), machineTargetMaxCount);
					})
					.thenWait(20)
					.pipe(function(_) {
						return manager.whenFinishedCurrentChanges()
							.thenWait(100)
							.then(function(_) {
								return assertEquals(manager.getWorkers().length, machineTargetMaxCount);
							});
					});
			})

			//Reduce down to one machine
			.pipe(function(_) {
				return InstancePool.setTotalWorkerCount(redis, 1)
					.thenWait(50)
					.pipe(function(_) {
						return InstancePool.toJson(redis)
							.then(function(jsondump :InstancePoolJson) {
								assertEquals(jsondump.getTargetWorkerCount(provider.id), Std.int(Math.max(1, machineTargetMinCount)));
								assertEquals(jsondump.getMaxWorkerCount(provider.id), machineTargetMaxCount);
								return true;
							});
					})

					.thenWait(50)
					.pipe(function(_) {
						return provider.whenFinishedCurrentChanges();
					})
					.thenWait(50)
					.pipe(function(_) {
						return InstancePool.getInstancesInPool(redis, provider.id)
							.then(function(out) {
								return assertEquals(out.filter(InstancePool.isAvailable).length, 1);
							});
					})
					.pipe(function(_) {
						assertEquals(provider.getTargetWorkerCount(), 1);
						return provider.whenFinishedCurrentChanges();
					})
					.thenWait(100)
					.then(function(_) {
						return assertEquals(provider.getTargetWorkerCount(), 1);
					})
					.thenWait(50)
					.pipe(function(_) {
						return manager.whenFinishedCurrentChanges()
							.thenWait(50)
							.then(function(_) {
								return assertEquals(manager.getActiveWorkers().length, Std.int(Math.max(1, machineTargetMinCount)));
							});
					});
			})

			//Change the billing cycle time, remove a machine, then add another
			//machine within the billing cycle. It should be the same machine
			.pipe(function(_) {
				var billingIncrement = new Minutes(100);
				var existingMachines = null;
				var newConfig = {maxWorkers:machineTargetMaxCount, minWorkers:machineTargetMinCount, priority:1, billingIncrement:billingIncrement};
				return provider.updateConfig(newConfig)
					.pipe(function(_) {
						//Bump up to 2 workers
						var testWorkerCount = 2;
						return InstancePool.setTotalWorkerCount(redis, testWorkerCount)
							.thenWait(50)
							.pipe(function(_) {
								return provider.whenFinishedCurrentChanges();
							})
							//Get the ids of the existing workers
							.pipe(function(_) {
								return InstancePool.toJson(redis)
									.then(function(jsondump :InstancePoolJson) {
										assertEquals(jsondump.getTargetWorkerCount(provider.id), testWorkerCount);
										existingMachines = jsondump.getRunningMachines(provider.id);
										assertEquals(jsondump.getAvailableMachines(provider.id).length, testWorkerCount);
										return true;
									});
							});
					})
					//Now down to a single machine
					.pipe(function(_) {
						return InstancePool.setTotalWorkerCount(redis, 1)
							.thenWait(20)
							.pipe(function(_) {
								return provider.whenFinishedCurrentChanges();
							})
							.pipe(function(_) {
								return InstancePool.toJson(redis)
									.then(function(jsondump :InstancePoolJson) {
										assertEquals(jsondump.getTargetWorkerCount(provider.id), 1);
										return true;
									});

							})
							.then(function(_) {
								return assertEquals(manager.getActiveWorkers().length, 1);
							});
					})
					.pipe(function(_) {
						return provider.whenFinishedCurrentChanges();
					})
					.thenWait(100)
					//Now up to 2 machines again. One of the new machines should be the old
					.pipe(function(_) {
						return InstancePool.setTotalWorkerCount(redis, 2)
							.thenWait(50)
							.pipe(function(_) {
								return provider.whenFinishedCurrentChanges();
							})
							.pipe(function(_) {
								return InstancePool.toJson(redis)
									.then(function(jsondump :InstancePoolJson) {
										var currentMachines = jsondump.getRunningMachines(provider.id);
										assertEquals(jsondump.getTargetWorkerCount(provider.id), 2);
										assertEquals(existingMachines.length, currentMachines.length);
										for (workerId in existingMachines) {
											assertTrue(currentMachines.has(workerId));
										}
										return true;
									});

							});
					})
					.thenTrue();
			})
			.thenTrue();
	}
}