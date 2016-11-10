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

import util.RedisTools;
import ccc.compute.InstancePool;
import ccc.compute.ComputeQueue;
import ccc.compute.ComputeTools;
import ccc.compute.JobTools;

import utils.TestTools;
import t9.abstracts.net.*;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;
using ccc.compute.InstancePool;

class TestScheduler extends TestComputeBase
{
	public function new() {}

	@timeout(200)
	public function testAddingRemovingMachines()
	{
		var redis = _redis;
		var poolId1 = new MachinePoolId('poolid1');
		var poolId2 = new MachinePoolId('poolid2');

		var priorities :Map<String, Int> = [
			poolId1 => 2,
			poolId2 => 1
		];
		var pools :Map<MachinePoolId, Array<WorkerDefinition>> = [
			poolId1 => [],
			poolId2 => [],
		];

		var jobs = [];
		for (i in 0...4) {
			jobs.push(JobTools.generateJobId());
		}

		for (poolId in pools.keys()) {
			for (i in 0...3) {
				var worker :WorkerDefinition = {
					id: new MachineId('${poolId}_machine${i}'),
					hostPrivate: new HostName('fake'),
					hostPublic: new HostName('fake'),
					ssh: {host: 'localhost', username: 'fakeusername'},
					docker: {host: 'localhost', protocol:'http', port:0}
				};
				pools[poolId].push(worker);
			}
		}

		var machineToDisable;
		return Promise.promise(true)
			.pipe(function(_) {
				var promises = [];
				for (poolId in pools.keys()) {
					for (worker in pools[poolId]) {
						promises.push(redis.addInstance(poolId, worker, {cpus:1, memory:0}));
					}
				}
				return Promise.whenAll(promises);
			})
			.pipe(function(_) {
				return redis.toJson();
			})
			.pipe(function(json) {
				//Validate the json
				for (poolId in pools.keys()) {
					assertTrue(json.pools.exists(function(pool) return pool.id == poolId));
					for (worker in pools[poolId]) {
						var jsonWorkers = json.pools.find(function(pool) return pool.id == poolId).instances;
						assertTrue(jsonWorkers.exists(function(e) return e.id == worker.id));
					}
				}
				machineToDisable = pools[poolId1][0];
				return redis.setWorkerStatus(machineToDisable.id, MachineStatus.Removing);
			})
			.pipe(function(machineId) {
				return redis.getInstanceStatus(machineToDisable.id);
			})
			.pipe(function(status) {
				assertEquals(status, MachineStatus.Removing);
				return redis.removeInstance(machineToDisable.id);
			})
			.pipe(function(_) {
				return redis.toJson();
			})
			.pipe(function(json) {
				json.removed_record = null;
				//Check the JSON dump string for the id string
				assertTrue(Json.stringify(json).indexOf(machineToDisable.id) == -1);
				return Promise.promise(true);
			})
			.thenTrue();
	}

	@timeout(200)
	public function testAddingRemovingJobs()
	{
		var redis = _redis;
		Assert.notNull(redis);
		var poolId1 = new MachinePoolId('poolid1');
		var poolId2 = new MachinePoolId('poolid2');

		var priorities :Map<MachinePoolId, Int> = [
			poolId1 => 2,
			poolId2 => 1
		];
		var pools :Map<MachinePoolId, Array<WorkerDefinition>> = [
			poolId1 => [],
			poolId2 => [],
		];

		var jobs = [];
		for (i in 0...7) {
			jobs.push(TestTools.createVirtualJob('job$i'));
		}
		var jobsToAdd = jobs.concat([]);
		var jobsAdded = [];

		var totalWorkerCount = 0;
		for (poolId in pools.keys()) {
			for (i in 0...3) {
				var worker :WorkerDefinition = {
					id: new MachineId('${poolId}_machine${i}'),
					hostPrivate: new HostName('fake'),
					hostPublic: new HostName('fake'),
					ssh: {host: 'localhost', username:'testname'},
					docker: {host: 'localhost', protocol: 'http', port:0}
				};
				totalWorkerCount++;
				pools[poolId].push(worker);
			}
		}


		function assertStuff(pendingLength :Int, workingLength :Int, availableCpus :Int, ?pos:haxe.PosInfos) :Promise<Dynamic> {
			//Count the number of cpus
			return Promise.promise(true)
				.pipe(function(_) {
					return InstancePool.toJson(redis);
				})
				.then(function(jsonDump :InstancePoolJson) {
					// trace('jsonDump=${jsonDump}');
					assertEquals(jsonDump.getAllAvailableCpus(), availableCpus, pos);
					return true;
				})
				.pipe(function(_) {
					return ComputeQueue.toJson(redis);
				})
				// .traceJson()
				.then(function(jsonDump :QueueJson) {
					assertEquals(jsonDump.working.length, workingLength, pos);
					assertEquals(jsonDump.pending.length, pendingLength, pos);
					return true;
				});
		}

		var machineToDisable;
		var jobToMachine = new Map<String,String>();
		var currentCpus = 0;
		var finished = 0;
		return Promise.promise(true)
			//This test was not written with autoscaling in mind
			.pipe(function(_) {
				return ComputeQueue.setAutoscaling(redis, false);
			})
			.pipe(function(_) {
				var promises = [];
				for (poolId in priorities.keys()) {
					promises.push(redis.setPoolPriority(poolId, priorities[poolId]));
				}
				return Promise.whenAll(promises);
			})
			.pipe(function(_) {
				var promises = [];
				for (poolId in pools.keys()) {
					for (worker in pools[poolId]) {
						promises.push(redis.addInstance(poolId, worker, {cpus:1,memory:0}));
					}
				}
				return Promise.whenAll(promises);
			})
			//Count the number of cpus
			.pipe(function(_) {
				return InstancePool.toJson(redis);
			})
			.then(function(jsonDump :InstancePoolJson) {
				currentCpus = jsonDump.getAllAvailableCpus();
				return true;
			})

			//Submit a job
			.pipe(function(_) {
				var job = jobsToAdd.shift();
				jobsAdded.push(job);
				return ComputeQueue.enqueue(redis, job);
			})
			.pipe(function(queueobject) {
				assertEquals(queueobject.id, jobsAdded[0].id);
				return Promise.promise(true);
			})
			//Count the number of cpus
			.pipe(function(_) {
				return InstancePool.toJson(redis);
			})

			.then(function(jsonDump :InstancePoolJson) {
				assertEquals(jsonDump.getAllAvailableCpus() + 1, currentCpus);
				return true;
			})

			//Submit the rest of the jobs
			.pipe(function(_) {
				return PromiseTools.chainPipePromises(jobsToAdd.map(function(job) {
					return function() {
						return ComputeQueue.enqueue(redis, job);
					}
				}));
			})

			//Check stuff
			.pipe(function(_) {
				var pending = jobs.length - totalWorkerCount;
				var working = totalWorkerCount;
				var available = 0;
				return assertStuff(pending, working, available);
			})

			//Then when a job is removed, the new one should go to working immediately
			.pipe(function(_) {
				finished++;
				//Remove, rather than finish, since the finish
				//process is more involved, and involved the Jobs manager.
				return ComputeQueue.removeJob(redis, jobs[0].id);
				// return ComputeQueue.finishJob(redis, jobs[0].id)
				// 	.pipe(function(queueobject :QueueJobDefinitionDocker) {
				// 		// trace('queueobject=${queueobject}');
				// 		return ComputeQueue.jobFinalized(redis, queueobject.computeJobId)
				// 			.pipe(function(_) {
				// 				// return ComputeQueue.removeJob(redis, queueobject.id);
				// 				return InstancePool.removeJob(redis, queueobject.computeJobId);
				// 			})
				// 			.pipe(function(_) {
				// 				return ComputeQueue.processPending(redis);
				// 			});
				// 	});
			})
			//Check stuff
			.pipe(function(_) {
				var pending = jobs.length - totalWorkerCount - finished;
				var working = totalWorkerCount;
				var available = 0;
				return assertStuff(pending, working, available);
			})

			//More removal
			.pipe(function(_) {
				finished++;
				return ComputeQueue.removeJob(redis, jobs[1].id);
			})

			//Check stuff
			.pipe(function(_) {
				var pending = Math.floor(Math.max(jobs.length - (totalWorkerCount + finished), 0));
				var available = Math.floor(Math.max(totalWorkerCount - (jobs.length - finished), 0));
				var working = totalWorkerCount - available;
				return assertStuff(pending, working, available);
			})

			.thenTrue();
	}
}