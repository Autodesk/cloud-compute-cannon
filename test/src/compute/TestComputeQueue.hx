package compute;

import haxe.Json;

import js.npm.RedisClient;

import promhx.Promise;

import ccc.compute.InstancePool;
import ccc.compute.ComputeQueue;
import ccc.compute.ComputeTools;
import ccc.compute.Definitions;

import t9.abstracts.net.*;

using promhx.PromiseTools;
using ccc.compute.InstancePool;
using Lambda;

typedef JobBlob = {
	var stuff:String;
	var jobId :JobId;
}

class TestComputeQueue extends TestComputeBase
{
	public static var POOL_ID1 :MachinePoolId = 'testPoolId1';
	public static var MACHINE1_P1 :MachineId = 'm1p1';
	public static var MACHINE2_P1 :MachineId = 'm2p1';

	public static function createWorkerDef(id :String)
	{
		var worker :WorkerDefinition = {
			id: Std.string(id),
			hostPrivate: new HostName('fake'),
			hostPublic: new HostName('fake'),
			ssh: {
				host:'fakehost' + id,
				username: 'fakeusername'
			},
			docker: {
				host:'fakehost' + id,
				port: 0,
				protocol: 'http'
			}
		};
		return worker;
	}

	/**
	 * Follows a single job (among others)
	 * as it is queued, worked on, and
	 * finished normally.
	 */
	@timeout(1000)
	public function testJobMovesThroughQueueNormally()
	{
		var redis = _redis;

		var maxDuration = 1;

		var jobCount = 6;
		var jobs = [];
		for (i in 0...jobCount) {
			var jobId :JobId = 'job' + i;
			var job :QueueJob<JobBlob> = {
				id: jobId,
				parameters: {cpus:1, maxDuration:maxDuration},
				item: {stuff: jobId, jobId: jobId}
			};
			jobs.push(job);
		};

		var numWorkers = 0;
		var workerParams :WorkerParameters = {cpus:2, memory:0};
		function addWorker(id :String) {
			numWorkers++;
			var worker = createWorkerDef(id);
			return InstancePool.addInstance(redis, POOL_ID1, worker, workerParams);
		}

		return Promise.promise(true)
			.pipe(function(_) {
				return ComputeQueue.setAutoscaling(redis, false);
			})
			.then(function(_) {
				_jobsManager = new MockJobs();
				_injector.injectInto(_jobsManager);
				return true;
			})
			//Worker pool priorities
			.pipe(function(_) {
				return InstancePool.setPoolPriority(redis, POOL_ID1, 1);
			})

			//Add two workers
			.pipe(function(_) {
				return addWorker(MACHINE1_P1);
			})
			.pipe(function(_) {
				return addWorker(MACHINE2_P1);
			})

			//Submit jobs
			.pipe(function(_) {
				return ComputeQueue.enqueue(redis, jobs[0]);
			})

			.pipe(function(_) {
				return ComputeQueue.toJson(redis)
					// .traceJson()
					.then(function(out :QueueJson) {
						assertEquals(out.pending.length, 0);
						assertEquals(out.working.length, 1);
						assertEquals(out.working[0].id, jobs[0].id);
						return out;
					});
			})

			.pipe(function(_) {
				return Promise.whenAll(jobs.slice(1).map(ComputeQueue.enqueue.bind(redis)));
			})

			.pipe(function(_) {
				return ComputeQueue.toJson(redis);
			})
			// .traceJson()
			.then(function(out :QueueJson) {
				assertEquals(out.working.length, numWorkers * workerParams.cpus);
				assertEquals(out.pending.length, jobs.length - out.working.length);
				assertTrue(out.working.exists(function(e) return e.id == jobs[0].id));
				assertTrue(out.working.exists(function(e) return e.id == jobs[1].id));
				assertTrue(out.working.exists(function(e) return e.id == jobs[2].id));
				return out;
			})

			//Check job status when processed
			//There should be two jobs processing, one still pending
			//since there aren't enough machines
			.pipe(function(_) {
				return ComputeQueue.processPending(redis);
			})
			// .pipe(function(_) {
			// 	return ComputeQueue.toJson(redis)
			// 		// .traceJson()
			// 		.then(function(out :QueueJson) {
			// 			assertEquals(out.pending.length, jobs.length - 4);
			// 			assertEquals(out.working.length, 4);
			// 			assertEquals(out.pending[0], jobs[jobs.length - 1].id);
			// 			assertEquals(out.pending[1], jobs[jobs.length - 2].id);
			// 			assertEquals(out.pending[2], jobs[jobs.length - 3].id);
			// 			assertEquals(out.working[0].id, jobs[0].id);
			// 			assertEquals(out.working[1].id, jobs[1].id);
			// 			assertEquals(out.working[2].id, jobs[2].id);
			// 			assertEquals(out.working[3].id, jobs[3].id);
			// 			return out;
			// 		});
			// })
			// .pipe(function(_) {
			// 	return InstancePool.toJson(redis)
			// 		// .traceJson()
			// 		.then(function(out) {
			// 			assertEquals(Reflect.fields(out.jobs).length, 4);
			// 			return out;
			// 		});
			// })
			// //Now finish a job
			// .pipe(function(_) {
			// 	return ComputeQueue.finishJob(redis, jobs[0].id, JobFinishedStatus.Success)
			// 	// 	.pipe(function(_) {
			// 		.then(function(out) {
			// 			var queueJob :QueueJobDefinitionDocker = cast out;
			// 			trace('queueJob=${queueJob}');
			// 			return queueJob.computeJobId;
			// 		})
			// 	// return ComputeQueue.finishAndFinalizeJob(redis, jobs[0].id, JobFinishedStatus.Success)
			// 		.pipe(function(computeJobId) {
			// 			var arr :Array<Promise<Dynamic>> = [InstancePool.toJson(redis), ComputeQueue.toJson(redis)];
			// 			return Promise.whenAll(arr)
			// 				.then(function(outs) {
			// 					var poolJson :InstancePoolJsonDump = cast outs[0];
			// 					var queueJson :QueueJson = cast outs[1];
			// 					// trace('POOL:');
			// 					// trace(Json.stringify(poolJson, null, '  '));
			// 					// trace('QUEUE:');
			// 					// trace(Json.stringify(queueJson, null, '  '));

			// 					// trace('computeJobId=${computeJobId}');
			// 					// trace('jobs[0].id=${jobs[0].id}');
			// 					// Json.stringify(poolJson);
			// 					assertEquals(Json.stringify(poolJson).indexOf(computeJobId), -1);
			// 					assertFalse(queueJson.isJobInQueue(jobs[0].id));

			// 					// trace('queueJson.pending=${queueJson.pending}');
			// 					// trace('jobCount=${jobCount}');
			// 					assertEquals(queueJson.pending.length, jobCount - 5);
			// 					assertEquals(queueJson.working.length, 4);
			// 					return true;
			// 			});
			// 		});
			// })
			// .pipe(function(_) {
			// 	return ComputeQueue.toJson(redis)
			// 		// .traceJson()
			// 		;
			// })

			// //TIMEOUTS!!!
			// .pipe(function(_) {
			// 	return ComputeQueue.checkTimeouts(redis);
			// 	//Need to manually push jobs through, normally this would be the reponsibility of the Job Object
			// })
			// .pipe(function(_) {
			// 	return ComputeQueue.toJson(redis)
			// 		.then(function(queueJson :QueueJson) {
			// 			trace('queueJson=\n${Json.stringify(queueJson, null, "  ")}');
			// 			//These jobs should all be removed from the instances since they timed out
			// 			assertFalse(queueJson.isJobInQueue(jobs[1].id));
			// 			assertFalse(queueJson.isJobInQueue(jobs[2].id));
			// 			assertFalse(queueJson.isJobInQueue(jobs[3].id));
			// 			return Promise.promise(true);
			// 		});
			// })
			// .pipe(function(_) {
			// 	return InstancePool.toJson(redis)
			// 		.then(function(poolJson :InstancePoolJsonDump) {
			// 			trace('poolJson=\n${Json.stringify(poolJson, null, "  ")}');
			// 			//These jobs should all be removed from the instances since they timed out
			// 			assertEquals(Json.stringify(poolJson).indexOf(jobs[1].id), -1);
			// 			assertEquals(Json.stringify(poolJson).indexOf(jobs[2].id), -1);
			// 			assertEquals(Json.stringify(poolJson).indexOf(jobs[3].id), -1);
			// 			assertEquals(poolJson.cpus[MACHINE1_P1], 2);
			// 			assertEquals(poolJson.cpus[MACHINE2_P1], 2);
			// 			return Promise.promise(true);
			// 		});
			// })
			.thenTrue();
	}

	public function new() {}
}