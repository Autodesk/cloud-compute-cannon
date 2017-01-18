package compute;

import haxe.Json;

import js.npm.RedisClient;
import js.npm.fsextended.FsExtended;

import promhx.Promise;

import ccc.compute.server.InstancePool;
import ccc.compute.server.ComputeQueue;
import ccc.compute.server.ComputeTools;
import ccc.compute.ServiceBatchCompute;
import ccc.compute.workers.WorkerProvider;
import ccc.compute.workers.WorkerProviderVagrant;

import utils.TestTools;

using promhx.PromiseTools;
using ccc.compute.server.InstancePool;
using ccc.compute.workers.WorkerProviderTools;
using StringTools;
using Lambda;

class TestCompleteJobSubmissionVagrant extends TestCompleteJobSubmissionBase
{
	public function new()
	{
		super();
	}

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
			.pipe(function (_) {
				if (storageService != null) {
					storageService.resetRootPath();
					Log.info('Job output cleanup: removing $jobOutputDirectory from ${storageService.getRootPath()}');
					return storageService.deleteDir(jobOutputDirectory);
				} else {
					Log.error("Job output cleanup failed; Storage Service reference is null.");
					return Promise.promise(true);
				}
			})
			.pipe(function(_) {
				return WorkerProviderVagrant.destroyAllVagrantMachines();
			});
	}

	@timeout(1200000) //20m
	public function testCompleteJobSubmissionVagrant()
	{
		return completeJobSubmission(2);
	}
}