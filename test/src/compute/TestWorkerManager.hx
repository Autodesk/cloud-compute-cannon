package compute;

import haxe.Json;
import haxe.unit.async.PromiseTest;

import js.Node;
import js.node.Path;
import js.node.Fs;
import js.npm.fsextended.FsExtended;
import js.npm.RedisClient;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.PromiseTools;
import promhx.RedisPromises;

import ccc.compute.InitConfigTools;
import ccc.compute.InstancePool;
import ccc.compute.ComputeTools;
import ccc.compute.ComputeQueue;
import ccc.compute.workers.WorkerManager;
import ccc.compute.workers.WorkerTools;
import ccc.compute.workers.WorkerProvider;
import ccc.compute.workers.WorkerProviderVagrant;
import ccc.compute.workers.VagrantTools;
import ccc.compute.workers.WorkerProviderBoot2Docker;
import ccc.compute.workers.WorkerProviderTools;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;
using ccc.compute.InstancePool;

class TestWorkerManager extends TestComputeBase
{
	public function new() {}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.then(function(_) {
				_workerManager = new WorkerManager();
				_injector.injectInto(_workerManager);
				return true;
			});
	}

	@timeout(500)
	public function testWorkerManagerAddRemoveMachines()
	{
		var redis = getClient();

		var injector = _injector;
		var manager = _workerManager;

		var worker1 = WorkerProviderBoot2Docker.getLocalDockerWorker();
		worker1.id = 'testMachine1';
		var worker2 = WorkerProviderBoot2Docker.getLocalDockerWorker();
		worker2.id = 'testMachine2';

		var params;

		var poolId = 'testpool';

		return Promise.promise(true)
			.pipe(function(_) {
				return ComputeQueue.setAutoscaling(getClient(), false);
			})
			.pipe(function(_) {
				return WorkerProviderTools.getWorkerParameters(worker1.docker)
					.then(function(v) {
						params = v;
						return true;
					});
			})

			.pipe(function(_) {
				return InstancePool.getAllWorkerIds(redis)
					.then(function(ids) {
						var val = assertEquals(ids.length, 0);
						return val;
					});
			})

			//Add the first machine
			.pipe(function(_) {
				return InstancePool.addInstance(redis, poolId, worker1, params)
					.thenWait(50)
					.then(function(_) {
						return assertEquals(manager.getWorkers().length, 1);
					});
			})

			//Add the second machine
			.pipe(function(_) {
				return InstancePool.addInstance(redis, poolId, worker2, params)
					.thenWait(50)
					.then(function(_) {
						return assertEquals(manager.getWorkers().length, 2);
					});
			})

			//Remove the first machine
			.pipe(function(_) {
				return InstancePool.removeInstance(redis, worker1.id)
					.thenWait(100)
					.then(function(_) {
						assertEquals(manager.getWorkers().length, 1);
						//But the machines marked as ready
						return assertEquals(manager.getWorkers().filter(WorkerTools.filterWorkerByStatus(MachineStatus.Available)).length, 1);
					});
			})

			//Mark machine ready to remove
			.pipe(function(_) {
				return InstancePool.setWorkerStatus(redis, worker2.id, MachineStatus.WaitingForRemoval)
					.thenWait(50)
					.then(function(_) {
						assertNotNull(manager.getWorker(worker2.id));
						return assertEquals(manager.getWorker(worker2.id).computeStatus, MachineStatus.WaitingForRemoval);
					});
			})

			.thenTrue();

	}
}