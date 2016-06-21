package compute;

import compute.MockWorkerProvider;

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

import ccc.compute.ServiceBatchCompute;
import ccc.compute.ComputeTools;
import ccc.compute.ComputeQueue;
import ccc.compute.InstancePool;
import ccc.compute.workers.WorkerProvider;
import ccc.compute.workers.WorkerProviderVagrant;
import ccc.compute.workers.VagrantTools;

import utils.TestTools;

import t9.abstracts.time.*;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;
using ccc.compute.InstancePool;

class TestScalingMock extends TestScalingBase
{
	public function new() super();

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				return _workerManager.dispose();
			})
			.pipe(function(_) {
				return _workerManager != null ? _workerManager.dispose() : Promise.promise(true);
			})
			.pipe(function(_) {
				return _workerProvider != null ? _workerProvider.dispose() : Promise.promise(true);
			})
			.pipe(function(_) {
				_workerManager = new MockWorkerManager();
				_injector.injectInto(_workerManager);
				_workerProvider = new MockWorkerProvider();
				_injector.injectInto(_workerProvider);
				return _workerProvider.ready;
			});
	}

	/**
	 * Currently this is NOT testing auto-scaling, which is now implemented,
	 * so its utility is questionable. If this test has problems, it may be
	 * worth removing all non-auto-scaling code and tests.
	 */
	@timeout(300)
	public function testMockProviderScaling()
	{
		MockWorkerProvider.TIME_MS_WORKER_CREATION = 100;
		var provider :MockWorkerProvider = cast _workerProvider;
		return Promise.promise(true)
			.pipe(function(_) {
				return ComputeQueue.setAutoscaling(_redis, false);
			})
			.pipe(function(_) {
				return _workerProvider.updateConfig({priority:1, minWorkers:0, maxWorkers:3, billingIncrement: 0});
			})
			.pipe(function(_) {
				_workerProvider.setWorkerCount(1);
				var whenEmpty = _workerProvider.whenFinishedCurrentChanges();
				return Promise.promise(true)
					.pipe(function(_) {
						assertFalse(whenEmpty.isResolved());
						return PromiseTools.delay(20);
					})
					.pipe(function(_) {
						assertFalse(whenEmpty.isResolved());
						return whenEmpty;
					})
					.pipe(function(_) {
						assertTrue(whenEmpty.isResolved());
						assertTrue(provider._currentWorkers.length() == 1);
						return Promise.promise(true);
					});
			})
			.thenTrue();
	}

	@timeout(500)
	public function testDeferred()
	{
		MockWorkerProvider.TIME_MS_WORKER_CREATION = 50;
		var provider :MockWorkerProvider = cast _workerProvider;
		var machineTargetCount = 2;
		var config :ProviderConfigBase = {
			priority: 1,
			maxWorkers: 3,
			minWorkers: 0,
			billingIncrement: new Milliseconds(100).toMinutes()
		};
		var redis = _redis;
		var workerIds;
		var deferredIds;
		return Promise.promise(true)
			.pipe(function(_) {
				return ComputeQueue.setAutoscaling(redis, false);
			})
			.pipe(function(_) {
				return _workerProvider.updateConfig(config);
			})
			//Set worker count=2
			.pipe(function(_) {
				return InstancePool.setTotalWorkerCount(redis, machineTargetCount)
					.pipe(function(_) {
						return provider.onceOnCountEquals(machineTargetCount);
					})
					.pipe(function(_) {
						return InstancePool.toJson(redis)
							.then(function(jsondump :InstancePoolJson) {
								assertEquals(jsondump.getTargetWorkerCount(provider.id), Std.int(Math.min(machineTargetCount, config.maxWorkers)));
								assertEquals(jsondump.getMaxWorkerCount(provider.id), config.maxWorkers);
								assertEquals(jsondump.getMinWorkerCount(provider.id), config.minWorkers);
								workerIds = jsondump.getRunningMachines(provider.id);
								assertEquals(workerIds.length, machineTargetCount);
								return true;
							});
					});
			})
			//Set worker count=1, but record the machines first, since when
			//we got back to 2 workers, it should use one of the deferred
			.pipe(function(_) {
				machineTargetCount = 1;
				return InstancePool.setTotalWorkerCount(redis, machineTargetCount)
					.pipe(function(_) {
						return provider.onceOnCountEquals(machineTargetCount);
					})
					.pipe(function(_) {
						return InstancePool.toJson(redis)
							.then(function(jsondump :InstancePoolJson) {
								assertEquals(jsondump.getTargetWorkerCount(provider.id), Std.int(Math.min(machineTargetCount, config.maxWorkers)));
								assertEquals(jsondump.getMaxWorkerCount(provider.id), config.maxWorkers);
								assertEquals(jsondump.getMinWorkerCount(provider.id), config.minWorkers);
								deferredIds = provider.getDeferredWorkerIds();
								assertEquals(deferredIds.length, 1);
								return true;
							});
					});
			})
			//Set worker back up to 2 workers, then 1, then 2, the new worker should be the
			//previously deferred worker
			.pipe(function(_) {
				machineTargetCount = 1;
				return InstancePool.setTotalWorkerCount(redis, machineTargetCount)
					.pipe(function(_) {
						return provider.onceOnCountEquals(machineTargetCount);
					});
			})
			.pipe(function(_) {
				machineTargetCount = 2;
				return InstancePool.setTotalWorkerCount(redis, machineTargetCount)
					.pipe(function(_) {
						return provider.onceOnCountEquals(machineTargetCount);
					})
					// .thenWait(50)
					.pipe(function(_) {
						return InstancePool.toJson(redis)
							.then(function(jsondump :InstancePoolJson) {
								assertEquals(jsondump.getTargetWorkerCount(provider.id), Std.int(Math.min(machineTargetCount, config.maxWorkers)));
								assertEquals(jsondump.getMaxWorkerCount(provider.id), config.maxWorkers);
								assertEquals(jsondump.getMinWorkerCount(provider.id), config.minWorkers);
								var newWorkerIds = jsondump.getRunningMachines(provider.id);
								assertEquals(newWorkerIds.length, workerIds.length);
								for (workerId in workerIds) {
									assertTrue(newWorkerIds.has(workerId));
								}
								return true;
							});
					});
			})
			//Now back down to 1 worker, then wait until the deferred worker
			//is actually removed, then up to 2 again, the new worker should
			//NOT be the deferred worker, but rather a new worker
			.pipe(function(_) {
				machineTargetCount = 1;
				return InstancePool.setTotalWorkerCount(redis, machineTargetCount)
					.pipe(function(_) {
						return provider.onceOnCountEquals(machineTargetCount);
					});
			})
			.thenWait(config.billingIncrement.toMilliseconds().toInt() + 50)
			.then(function(_) {
				assertEquals(provider.getDeferredWorkerIds().length, 0);
				return true;
			})
			.pipe(function(_) {
				machineTargetCount = 2;
				return InstancePool.setTotalWorkerCount(redis, machineTargetCount)
					.pipe(function(_) {
						return provider.onceOnCountEquals(machineTargetCount);
					})
					.pipe(function(_) {
						return InstancePool.toJson(redis)
							.then(function(jsondump :InstancePoolJson) {
								assertEquals(jsondump.getTargetWorkerCount(provider.id), Std.int(Math.min(machineTargetCount, config.maxWorkers)));
								assertEquals(jsondump.getMaxWorkerCount(provider.id), config.maxWorkers);
								assertEquals(jsondump.getMinWorkerCount(provider.id), config.minWorkers);
								var newWorkerIds = jsondump.getRunningMachines(provider.id);
								for (workerId in workerIds) {
									newWorkerIds.remove(workerId);
								}
								assertEquals(newWorkerIds.length, 1);
								return true;
							});
					});
			})
			.thenTrue();
	}

	@timeout(120000)
	public function XXtestScalingMock()
	{
		return baseTestScalingMachines();
	}
}