package compute;

import haxe.Json;

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

import ccc.compute.ServiceBatchCompute;
import ccc.compute.InstancePool;
import ccc.compute.ComputeTools;
import ccc.compute.workers.WorkerProvider;
import ccc.compute.workers.WorkerProviderVagrant;
import ccc.compute.workers.VagrantTools;
import ccc.storage.ServiceStorage;
import ccc.storage.ServiceStorageLocalFileSystem;

import utils.TestTools;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;
using ccc.compute.InstancePool;

class TestScalingVagrant extends TestScalingBase
{
	public function new() super();

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				return WorkerProviderVagrant.destroyAllVagrantMachines();
			})
			.pipe(function(_) {
				_workerProvider = new WorkerProviderVagrant();
				_injector.injectInto(_workerProvider);
				return _workerProvider.ready;
			});
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		return super.tearDown()
			.pipe(function(_) {
				return WorkerProviderVagrant.destroyAllVagrantMachines();
			});
	}

	@timeout(600000)//10 minutes
	public function testScalingVagrant()
	{
		return baseTestScalingMachines();
	}
}