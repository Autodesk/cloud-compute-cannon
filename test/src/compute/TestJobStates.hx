package compute;

import haxe.Json;

import js.npm.RedisClient;

import promhx.Promise;

import ccc.compute.InstancePool;
import ccc.compute.ComputeQueue;
import ccc.compute.ComputeTools;
import ccc.compute.workers.WorkerManager;

import compute.TestComputeQueue.*;

using promhx.PromiseTools;
using ccc.compute.InstancePool;
using Lambda;

class TestJobStates extends TestComputeBase
{
	override public function setup() :Null<Promise<Bool>>
	{
		var numWorkers = 0;
		var workerParams :WorkerParameters = {cpus:2, memory:0};
		function addWorker(id :String) {
			var redis = _injector.getValue(js.npm.RedisClient);
			numWorkers++;
			var worker = createWorkerDef(id);
			return InstancePool.addInstance(redis, POOL_ID1, worker, workerParams);
		}

		return super.setup()
			.pipe(function(_) {
				var redis = _injector.getValue(js.npm.RedisClient);
				return ComputeQueue.setAutoscaling(redis, true);
			})
			.then(function(_) {
				_jobsManager = new MockJobs();
				_injector.injectInto(_jobsManager);
				return true;
			})
			//Worker pool priorities
			.pipe(function(_) {
				var redis = _injector.getValue(js.npm.RedisClient);
				return InstancePool.registerComputePool(redis, POOL_ID1, 1, 10, 2, 50);
			})
			//Add two workers
			.pipe(function(_) {
				return addWorker(MACHINE1_P1)
					.pipe(function(_) {
						return addWorker(MACHINE2_P1);
					});
			});
	}

	@timeout(5000)
	public function testJobKilled()
	{
		var maxDuration = 1;

		var jobCount = 10;
		var jobs = [];
		for (i in 0...jobCount) {
			var jobId :JobId = 'job' + i;
			var job :QueueJob<DockerJobDefinition> = {
				id :jobId,
				parameters: {cpus:1, maxDuration:maxDuration},
				item: {
					jobId: jobId,
					image: null
				}
			};
			jobs.push(job);
		};

		var jobManager :MockJobs = cast _jobsManager;
		jobManager.jobDuration = 10000;

		var redis = _injector.getValue(js.npm.RedisClient);
		return Promise.promise(true)
			//Submit jobs
			.pipe(function(_) {
				return ComputeQueue.enqueue(redis, jobs[0])
					.pipe(function(_) {
						return ComputeQueue.processPending(redis);
					});
			})
			//Wait a while, the job should still be running
			.thenWait(300)
			.pipe(function(_) {
				return ComputeQueue.toJson(redis)
					// .traceJson()
					.then(function(out :QueueJson) {
						assertEquals(out.pending.length, 0);
						assertEquals(out.working.length, 1);
						assertEquals(out.working[0].id, jobs[0].id);
						var job :MockJob = jobManager.getJob(jobManager.getComputeJobIds()[0]);
						assertEquals(job.jobId, jobs[0].id);
						return out;
					});
			})
			//Kill the job
			.pipe(function(_) {
				var job :MockJob = jobManager.getJob(jobManager.getComputeJobIds()[0]);
				return job.kill();
			})
			.thenWait(50)
			.pipe(function(_) {
				assertEquals(0, jobManager.getComputeJobIds().length);
				return Promise.promise(true);
			})
			.pipe(function(_) {
				return ComputeQueue.getStatus(redis, jobs[0].id)
					.then(function(jobStatusBlob :JobStatusUpdate) {
						assertEquals(jobStatusBlob.jobId, jobs[0].id);
						assertEquals(jobStatusBlob.JobStatus, JobStatus.Finished);
						assertEquals(jobStatusBlob.JobFinishedStatus, JobFinishedStatus.Killed);
						return true;
					});
			})
			.thenTrue();
	}

	@timeout(5000)
	public function testJobFailedInBatchComputeSetup()
	{
#if PromhxExposeErrors
		#error 'Cannot have -D PromhxExposeErrors because the throw error will be exposed rather than handled by the internal system';
#end
		var maxDuration = 1;

		var jobCount = 10;
		var jobs = [];
		for (i in 0...jobCount) {
			var jobId :JobId = 'job' + i;
			var job :QueueJob<DockerJobDefinition> = {
				id :jobId,
				parameters: {cpus:1, maxDuration:maxDuration},
				item: {
					jobId: jobId,
					image: null
				}
			};
			jobs.push(job);
		};

		var jobManager :MockJobs = cast _jobsManager;
		jobManager.jobDuration = 10000;
		jobManager.jobError = 'Fake error! Ignore me in the logs, it is too hard to silence just this error message but also not miss actual errors. Move along.';

		var redis = _injector.getValue(js.npm.RedisClient);
		return Promise.promise(true)
			//Submit jobs
			.pipe(function(_) {
				return ComputeQueue.enqueue(redis, jobs[0])
					.pipe(function(_) {
						return ComputeQueue.processPending(redis);
					});
			})
			//Wait a while, the job should still be running
			.thenWait(100)
			.pipe(function(_) {
				return ComputeQueue.toJson(redis)
					// .traceJson()
					.then(function(out :QueueJson) {
						assertEquals(out.pending.length, 0);
						assertEquals(out.working.length, 0);
						assertEquals(jobManager.getComputeJobIds().length, 0);
						return out;
					});
			})
			.pipe(function(_) {
				return ComputeQueue.getStatus(redis, jobs[0].id)
					.then(function(jobStatusBlob :JobStatusUpdate) {
						assertEquals(jobStatusBlob.jobId, jobs[0].id);
						assertEquals(jobStatusBlob.JobStatus, JobStatus.Finished);
						//Quotes are added. Don't know why, but hacking around it.
						if (jobStatusBlob.error.startsWith('"')) {
							jobStatusBlob.error = jobStatusBlob.error.substr(1, jobStatusBlob.error.length - 2);
						}
						assertEquals(jobStatusBlob.error, jobManager.jobError);
						assertEquals(jobStatusBlob.JobFinishedStatus, JobFinishedStatus.Failed);
						return true;
					});
			})
			.thenTrue();
	}

	public function new() {}
}