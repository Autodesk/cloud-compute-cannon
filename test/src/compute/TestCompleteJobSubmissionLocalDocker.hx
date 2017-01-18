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
import ccc.compute.workers.WorkerProviderBoot2Docker;

import utils.TestTools;

using promhx.PromiseTools;
using ccc.compute.server.InstancePool;
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
		var config :ServiceConfigurationWorkerProvider = {
			type: ServiceWorkerProviderType.boot2docker,
			maxWorkers: 1,
			minWorkers: 0,
			priority: 1,
			billingIncrement: 0
		};
		_workerProvider = new WorkerProviderBoot2Docker(config);
		return super.setup()
			.pipe(function(_) {
				_injector.injectInto(_workerProvider);
				return _workerProvider.ready;
			});
	}

	@timeout(600000) //10m
	public function testCompleteJobSubmissionLocalDocker()
	{
		return completeJobSubmission(1);
	}
}