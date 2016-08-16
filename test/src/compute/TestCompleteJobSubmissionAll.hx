package compute;

import haxe.Json;

import js.npm.RedisClient;
import js.npm.fsextended.FsExtended;

import promhx.Promise;

import ccc.compute.InstancePool;
import ccc.compute.ComputeQueue;
import ccc.compute.ComputeTools;
import ccc.compute.ServiceBatchCompute;
import ccc.compute.workers.*;
import ccc.compute.workers.WorkerProviderBoot2Docker;

import utils.TestTools;

using promhx.PromiseTools;
using ccc.compute.InstancePool;
using ccc.compute.workers.WorkerProviderTools;
using StringTools;
using Lambda;

class TestCompleteJobSubmissionAll extends TestCompleteJobSubmissionBase
{
	static var NUM_WORKERS = 2;
	public function new()
	{
		super();
	}

	@timeout(600000) //10m
	public function testCompleteJobSubmissionAmazon()
	{
		return Promise.promise(true)
			.pipe(function(_) {
				var config = TestPkgCloudAws.getConfig();
				assertTrue(config != null);
				var provider = new WorkerProviderPkgCloud(config);
				_injector.injectInto(provider);
				_injector.map(WorkerProvider).toValue(_workerProvider);
				return _workerProvider.ready;
			})
			.pipe(function(_) {
				return completeJobSubmission(NUM_WORKERS);
			});
	}

	@timeout(600000) //10m
	public function testCompleteJobSubmissionVagrant()
	{
		return Promise.promise(true)
			.pipe(function(_) {
				_workerProvider = new WorkerProviderVagrant();
				_injector.injectInto(_workerProvider);
				return _workerProvider.ready;
			})
			.pipe(function(_) {
				return completeJobSubmission(NUM_WORKERS);
			});
	}

	@timeout(600000) //10m
	public function testCompleteJobSubmissionLocalDocker()
	{
		return Promise.promise(true)
			.pipe(function(_) {
				_workerProvider = cast WorkerProviderBoot2Docker.getService(getClient());
				_injector.injectInto(_workerProvider);
				return _workerProvider.ready;
			})
			.pipe(function(_) {
				return completeJobSubmission(NUM_WORKERS);
			});
	}
}