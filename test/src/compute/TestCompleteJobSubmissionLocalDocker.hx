package compute;

import haxe.Json;

import js.npm.RedisClient;
import js.npm.FsExtended;

import promhx.Promise;

import ccc.compute.InstancePool;
import ccc.compute.ComputeQueue;
import ccc.compute.ComputeTools;
import ccc.compute.ServiceBatchCompute;
import ccc.compute.workers.WorkerProvider;
import ccc.compute.workers.WorkerProviderBoot2Docker;

import utils.TestTools;

using promhx.PromiseTools;
using ccc.compute.InstancePool;
using ccc.compute.workers.WorkerProviderTools;
using StringTools;
using Lambda;

class TestCompleteJobSubmissionLocalDocker extends TestCompleteJobSubmissionBase
{
	public function new()
	{
		super();
	}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				var config :ServiceConfigurationWorkerProvider = {
					type: ServiceWorkerProviderType.boot2docker,
					maxWorkers: 1,
					minWorkers: 0,
					priority: 1,
					billingIncrement: 0
				};
				_workerProvider = new WorkerProviderBoot2Docker(config);
				_injector.injectInto(_workerProvider);
				return _workerProvider.ready;
			});
	}

	/**
	 * This is currently disabled since we no longer use SFTP for accessing
	 * the local provider storage. Instead we use direct file system access
	 * via mounted volumes. This means that mounted volumes must be correct.
	 */
	// @timeout(1000)
	// public function DISABLEDtestSftpConfiguredCorrectly()
	// {
	// 	return WorkerProviderBoot2Docker.isSftpConfigInLocalDockerMachine()
	// 		.then(function(ok) {
	// 			assertTrue(ok);
	// 			return true;
	// 		});
	// }

	@timeout(600000) //10m
	public function testCompleteJobSubmissionLocalDocker()
	{
		return completeJobSubmission(1);
	}
}