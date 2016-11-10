package compute;

import js.npm.RedisClient;

import promhx.Promise;

import ccc.compute.InstancePool;
import ccc.compute.ComputeTools;
import ccc.compute.ComputeQueue;
import ccc.compute.server.ServerCommands;
import ccc.compute.workers.WorkerManager;
import ccc.compute.workers.WorkerProvider;
import ccc.compute.execution.Jobs;

import t9.abstracts.time.*;
import t9.abstracts.net.*;

using promhx.PromiseTools;
using ccc.compute.InstancePool;

class TestInstancePool extends TestComputeBase
{
	public function new() {}

	@timeout(10000)
	public function testWorkerFailureCycle()
	{
		var providerConfig :ServiceConfigurationWorkerProvider = {
			type: ServiceWorkerProviderType.mock,
			maxWorkers: 3,
			minWorkers: 1,
			priority: 2,
			billingIncrement: new Minutes(0)
		}

		var redis = _redis;
		Assert.notNull(redis);

		var jobId :JobId = 'jobIsFOOBAR';
		var job :QueueJob<MockJobBlob> = {
			id: jobId,
			parameters: {cpus:1, maxDuration:100000},
			item: {stuff: jobId, jobId: jobId}
		};

		return Promise.promise(true)
			.pipe(function(_) {
				return MockTools.createMockStack(_injector, providerConfig)
					.then(function(stack) {
						_stack = stack;
						var jobs :MockJobs = cast _stack.jobs;
						jobs.jobDuration = 2000;
						return true;
					});
			})
			.pipe(function(_) {
				return InstancePool.registerComputePool(redis, providerConfig.type, providerConfig.priority, providerConfig.maxWorkers, providerConfig.minWorkers, providerConfig.billingIncrement);
			})
			.thenWait(100)
			.pipe(function(_) {
				return _stack.provider.whenFinishedCurrentChanges();
			})
			.pipe(function(_) {
				//Start a long running job
				return ComputeQueue.enqueue(redis, job);
			})
			// .pipe(function(_) {
			// 	return ServerCommands.traceStatus(redis);
			// })
			.thenWait(50)
			// .pipe(function(_) {
			// 	return ServerCommands.traceStatus(redis);
			// })
			// .pipe(function(_) {
			// 	return ComputeQueue.toJson(redis)
			// 		.then(function(blob) {
			// 			trace('blob=${Json.stringify(blob, null, "  ")}');
			// 			return true;
			// 		});
			// })
			.pipe(function(_) {
				//Get the machine associated with the job and fail it
				return ComputeQueue.getWorkerIdForJob(redis, job.id)
					.pipe(function(workerId) {
						assertNotNull(workerId);
						return InstancePool.workerFailed(redis, workerId)
							.thenWait(50)
							.pipe(function(_) {
								return InstancePool.toRawJson(redis);
							})
							.then(function(blob) {
								var blobString = Json.stringify(blob, null, "\t");
								assertEquals(blobString.indexOf(workerId), -1);
								return true;
							});
					});
			})
			// .pipe(function(_) {
			// 	return ServerCommands.traceStatus(redis);
			// })
			.thenTrue();
	}

	public function testRegistration()
	{
		var providerConfig :ServiceConfigurationWorkerProvider = {
			type: ServiceWorkerProviderType.test1,
			maxWorkers: 3,
			minWorkers: 1,
			priority: 2,
			billingIncrement: new Minutes(0)
		}

		var redis = _redis;
		Assert.notNull(redis);

		return Promise.promise(true)
			.pipe(function(_) {
				return ComputeQueue.setAutoscaling(redis, false);
			})
			.pipe(function(_) {
				return InstancePool.registerComputePool(redis, providerConfig.type, providerConfig.priority, providerConfig.maxWorkers, providerConfig.minWorkers, providerConfig.billingIncrement);
			})
			.pipe(function(_) {
				return InstancePool.getProviderConfig(redis, providerConfig.type);
			})
			.then(function(out) {
				assertNotNull(out);
				assertEquals(out.type, providerConfig.type);
				assertEquals(out.maxWorkers, providerConfig.maxWorkers);
				assertEquals(out.minWorkers, providerConfig.minWorkers);
				assertEquals(out.priority, providerConfig.priority);
				return true;
			});
	}

	public function testAddRemoveInstances()
	{
		var redis = _redis;
		assertNotNull(redis);

		var POOL_ID = new MachinePoolId('testPoolId');

		function addWorker(id :Int) {
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
			var workerParams :WorkerParameters = {
				cpus: 2,
				memory: 0
			}
			return InstancePool.addInstance(redis, POOL_ID, worker, workerParams);
		}

		return Promise.promise(true)
			.pipe(function(_) {
				return ComputeQueue.setAutoscaling(redis, false);
			})
			//Add worker
			.pipe(function(_) {
				return addWorker(1);
			})
			.pipe(function(_) {
				return InstancePool.getInstancesInPool(redis, POOL_ID);
			})
			.pipe(function(result) {
				assertEquals(result.length, 1);
				return InstancePool.existsMachine(redis, Std.string(1));
			})
			.then(function(exists) {
				assertTrue(exists);
				return true;
			})
			.pipe(function(_) {
				return InstancePool.existsMachine(redis, Std.string(2));
			})
			.then(function(exists) {
				assertTrue(!exists);
				return true;
			})
			//Add worker
			.pipe(function(_) {
				return addWorker(2);
			})
			.pipe(function(_) {
				return InstancePool.getInstancesInPool(redis, POOL_ID);
			})
			.pipe(function(result) {
				assertEquals(result.length, 2);
				return Promise.promise(true);
			})
			//Add worker
			.pipe(function(_) {
				return addWorker(3);
			})
			.pipe(function(_) {
				return InstancePool.getInstancesInPool(redis, POOL_ID);
			})
			.pipe(function(result) {
				assertEquals(result.length, 3);
				assertEquals(result.filter(InstancePool.isAvailable).length, 3);
				return Promise.promise(true);
			})

			//Change worker state
			.pipe(function(_) {
				return InstancePool.setWorkerStatus(redis, Std.string(2), MachineStatus.WaitingForRemoval);
			})
			.pipe(function(_) {
				return InstancePool.getInstancesInPool(redis, POOL_ID);
			})
			.pipe(function(result) {
				assertEquals(result.length, 3);
				assertEquals(result.filter(InstancePool.isAvailable).length, 2);
				assertEquals(result.filter(InstancePool.isStatus([MachineStatus.WaitingForRemoval])).length, 1);
				return Promise.promise(true);
			})

			//Remove worker
			.pipe(function(_) {
				return InstancePool.removeInstance(redis, Std.string(1));
			})
			.pipe(function(_) {
				return InstancePool.getInstancesInPool(redis, POOL_ID);
			})
			.pipe(function(result) {
				assertEquals(result.length, 2);
				assertEquals(result.filter(InstancePool.isAvailable).length, 1);
				assertEquals(result.filter(InstancePool.isStatus([MachineStatus.WaitingForRemoval])).length, 1);
				return Promise.promise(true);
			})

			.thenTrue();
	}

	/**
	 * Adds and removes jobs to the ComputePool, checks
	 * that the machine chosen for jobs is correct.
	 * @return [description]
	 */
	@timeout(300)
	public function testMachinePriority()
	{
		var redis = _redis;
		assertNotNull(redis);

		var POOL_ID1 = new MachinePoolId('testPoolId1');
		var POOL_ID2 = new MachinePoolId('testPoolId2');

		var machine1P1 :MachineId = 'm1p1';
		var machine2P1 :MachineId = 'm2p1';
		var machine1P2 :MachineId = 'm1p2';
		var machine2P2 :MachineId = 'm2p2';

		var maxDuration = 1;
		var job1 :{id:ComputeJobId, params :JobParams} = {
			id :'job1cpus1',
			params: {cpus:1, maxDuration:maxDuration}
		};

		var job2 :{id:ComputeJobId, params :JobParams} = {
			id :'job2cpus2',
			params: {cpus:2, maxDuration:maxDuration}
		};

		var job3 :{id:ComputeJobId, params :JobParams} = {
			id :'job3cpus3',
			params: {cpus:3, maxDuration:maxDuration}
		};

		var job4 :{id:ComputeJobId, params :JobParams} = {
			id :'job4cpus2',
			params: {cpus:2, maxDuration:maxDuration}
		};

		var job5 :{id:ComputeJobId, params :JobParams} = {
			id :'job5cpus1',
			params: {cpus:1, maxDuration:maxDuration}
		};

		function addWorker(id :String, poolId :MachinePoolId) {
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
			var workerParams :WorkerParameters = {
				cpus: 2,
				memory: 0
			}
			return InstancePool.addInstance(redis, poolId, worker, workerParams);
		}

		return Promise.promise(true)
			.pipe(function(_) {
				return ComputeQueue.setAutoscaling(redis, false);
			})
			//Priorities
			.pipe(function(_) {
				return InstancePool.setPoolPriority(redis, POOL_ID1, 1);
			})
			.pipe(function(_) {
				return InstancePool.setPoolPriority(redis, POOL_ID2, 2);
			})

			//Add workers
			.pipe(function(_) {
				return addWorker(machine1P1, POOL_ID1);
			})
			.pipe(function(_) {
				return addWorker(machine1P2, POOL_ID2);
			})
			.pipe(function(_) {
				return addWorker(machine2P2, POOL_ID2);
			})
			.pipe(function(_) {
				return addWorker(machine2P1, POOL_ID1);
			})

			//Check workers
			.pipe(function(_) {
				return InstancePool.getInstancesInPool(redis, POOL_ID1);
			})
			.pipe(function(result) {
				assertEquals(result.length, 2);
				assertEquals(result.filter(InstancePool.isAvailable).length, 2);
				return Promise.promise(true);
			})
			.pipe(function(_) {
				return InstancePool.getInstancesInPool(redis, POOL_ID2);
			})
			.pipe(function(result) {
				assertEquals(result.length, 2);
				assertEquals(result.filter(InstancePool.isAvailable).length, 2);
				return Promise.promise(true);
			})


			//Submit jobs, and check that the machines are correct
			//Add job1
			.pipe(function(_) {
				return InstancePool.findMachineForJob(redis, job1.params);
			})
			.pipe(function(machineId :MachineId) {
				assertEquals(machineId, machine1P1);
				return InstancePool.addJobToMachine(redis, job1.id, job1.params, machineId);
			})
			.pipe(function(_) {
				return InstancePool.toJson(redis);
			})
			.pipe(function(state) {
				assertEquals(state.getMachineRunningJob(job1.id).id, machine1P1);
				return Promise.promise(true);
			})

			//Add job2
			.pipe(function(_) {
				return InstancePool.findMachineForJob(redis, job2.params);
			})
			.pipe(function(machineId :MachineId) {
				assertEquals(machineId, machine2P1);
				return InstancePool.addJobToMachine(redis, job2.id, job2.params, machineId);
			})
			.pipe(function(_) {
				return InstancePool.toJson(redis);
			})
			// .traceJson()
			.pipe(function(state) {
				assertEquals(state.getMachineRunningJob(job2.id).id, machine2P1);
				return Promise.promise(true);
			})

			//Add job3 (try to, but it cannot because it's requirements are too big)
			//If this happens via the queue, it should go to the back of the queue
			.pipe(function(_) {
				return InstancePool.findMachineForJob(redis, job3.params);
			})
			.pipe(function(machineId) {
				assertIsNull(machineId);
				return Promise.promise(true);
			})

			//Add job4
			.pipe(function(_) {
				return InstancePool.findMachineForJob(redis, job4.params);
			})
			.pipe(function(machineId) {
				assertEquals(machineId, machine1P2);
				return InstancePool.addJobToMachine(redis, job4.id, job4.params, machineId);
			})
			.pipe(function(_) {
				return InstancePool.toJson(redis);
			})
			.pipe(function(state) {
				assertEquals(state.getMachineRunningJob(job4.id).id, machine1P2);
				return Promise.promise(true);
			})

			//Mark a machine as ready for removal
			.pipe(function(_) {
				return InstancePool.setWorkerStatus(redis, machine1P1, MachineStatus.WaitingForRemoval);
			})

			//Add another job (5), it should go to the removed machine now
			.pipe(function(_) {
				return InstancePool.findMachineForJob(redis, job5.params);
			})
			.pipe(function(machineId) {
				assertEquals(machineId, machine2P2);
				return InstancePool.addJobToMachine(redis, job5.id, job5.params, machineId);
			})
			.pipe(function(_) {
				return InstancePool.toJson(redis);
			})
			.pipe(function(state) {
				assertEquals(state.getMachineRunningJob(job5.id).id, machine2P2);
				return Promise.promise(true);
			})

			//Remove a job
			.pipe(function(_) {
				return InstancePool.removeJob(redis, job5.id);
			})
			.pipe(function(_) {
				return InstancePool.toJson(redis);
			})
			.pipe(function(state) {
				assertTrue(state.toString().indexOf(job5.id) == -1);
				assertEquals(state.getAvailableCpus(machine2P2), 2);
				return Promise.promise(true);
			})

			.thenTrue();
	}
}