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

import ccc.compute.InstancePool;
import ccc.compute.ComputeQueue;
import ccc.compute.ComputeTools;
import ccc.compute.ConnectionToolsRedis;
import ccc.compute.workers.WorkerManager;
import ccc.compute.workers.WorkerProvider;
import ccc.storage.ServiceStorage;
import ccc.storage.ServiceStorageLocalFileSystem;

import utils.TestTools;

import t9.abstracts.time.*;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;
using ccc.compute.InstancePool;

class TestAutoscaling extends TestComputeBase
{
	public function new() {}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				var config = {
					type: ServiceWorkerProviderType.mock,
					minWorkers: 0,
					maxWorkers: 3,
					priority: 1,
					billingIncrement: new Minutes(0)
				}
				_workerProvider = new compute.MockWorkerProvider(config);
				_injector.injectInto(_workerProvider);
				return _workerProvider.ready;
			});
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		_injector = null;
		return super.tearDown()
			.pipe(function(_) {
				return _workerProvider == null ? Promise.promise(true) : _workerProvider.dispose();
			});
	}

	@timeout(5000)
	public function testAutoscaling()
	{
		return ConnectionToolsRedis.getRedisClient()
			.pipe(function(redis) {
				var provider :compute.MockWorkerProvider = cast _workerProvider;

				var billingIncrementMilliseconds = 50.0;
				var currentTargetNumberOfWorkers = 0;

				var config = {
					minWorkers: 0,
					maxWorkers: 0,
					priority: 1,
					billingIncrement: new Milliseconds(100).toMinutes()
				}

				var jobs = [];
				for (i in 0...14) {
					jobs.push(TestTools.createVirtualJob('job$i'));
				}
				var currentSubmittedJobIndex = 0;

				function assertCorrectWorkerCount(actualWorkerCount :Int, ?infos : haxe.PosInfos) {
					if (actualWorkerCount > config.maxWorkers) {
						assertTrue(false, infos);
					} else if (actualWorkerCount < config.minWorkers) {
						assertTrue(false, infos);
					} else {
						var target = Math.floor(Math.min(currentTargetNumberOfWorkers, config.maxWorkers));
						target = Math.floor(Math.max(target, config.minWorkers));
						assertTrue(target == actualWorkerCount, infos);
					}
				}

				return Promise.promise(true)
					.pipe(function(_) {
						return provider.updateConfig(config);
					})
					.pipe(function(_) {
						return provider.ready;
					})
					//This is false by default until I add this test
					.pipe(function(_) {
						return ComputeQueue.setAutoscaling(redis, true);
					})
					//Basic checks to start
					.pipe(function(_) {
						return _workerProvider.updateConfig(config)
							.pipe(function(_) {
								return InstancePool.toJson(redis)
									.then(function(jsondump :InstancePoolJson) {
										assertCorrectWorkerCount(jsondump.getTargetWorkerCount(provider.id));
										assertTrue(currentTargetNumberOfWorkers == jsondump.totalTargetInstances);
										return true;
									});
							});
					})
					//Increase the max number of machines
					.pipe(function(_) {
						config.maxWorkers = 4;
						return _workerProvider.setMaxWorkerCount(config.maxWorkers)
							.pipe(function(_) {
								//Just make sure we still have no machines, since there are no jobs, and no minimal number of workers
								return InstancePool.toJson(redis)
									.then(function(jsondump :InstancePoolJson) {
										assertTrue(jsondump.getTargetWorkerCount(provider.id) == 0);
										assertTrue(provider._currentWorkers.length() == 0);
										assertTrue(currentTargetNumberOfWorkers == jsondump.totalTargetInstances);
										return true;
									});
							});
					})
					//Now add a job
					.pipe(function(_) {
						currentTargetNumberOfWorkers = 1;
						return ComputeQueue.enqueue(redis, jobs[currentSubmittedJobIndex++])
							.thenWait(20)
							.pipe(function(_) {
								return provider.whenFinishedCurrentChanges();
							})
							.pipe(function(_) {
								return InstancePool.toJson(redis)
									.then(function(jsondump :InstancePoolJson) {
										assertTrue(jsondump.getTargetWorkerCount(provider.id) == currentTargetNumberOfWorkers);
										assertCorrectWorkerCount(jsondump.getTargetWorkerCount(provider.id));
										assertTrue(currentTargetNumberOfWorkers == jsondump.totalTargetInstances);
										return true;
									});
							});
					})
					//Now add two more jobs for a total of 3 jobs, and 2 workers
					.pipe(function(_) {
						currentTargetNumberOfWorkers = Math.ceil(3.0 / MockWorkerProvider.CPUS_PER_WORKER);
						return ComputeQueue.enqueue(redis, jobs[currentSubmittedJobIndex++])
							.pipe(function(_) {
								return ComputeQueue.enqueue(redis, jobs[currentSubmittedJobIndex++]);
							})
							.thenWait(20)
							.pipe(function(_) {
								return provider.whenFinishedCurrentChanges();
							})
							.pipe(function(_) {
								return InstancePool.toJson(redis)
									.then(function(jsondump :InstancePoolJson) {
										assertEquals(jsondump.getTargetWorkerCount(provider.id), currentTargetNumberOfWorkers);
										assertCorrectWorkerCount(jsondump.getTargetWorkerCount(provider.id));
										assertEquals(currentTargetNumberOfWorkers, jsondump.totalTargetInstances);
										return true;
									});
							});
					})
					//Now finished the jobs
					.pipe(function(_) {
						currentTargetNumberOfWorkers = config.minWorkers;
						var promises = [];
						for (i in 0...currentSubmittedJobIndex) {
							promises.push(ComputeQueue.removeJob(redis, jobs[i].id));
						}
						return Promise.whenAll(promises)
							.thenWait(20)
							.pipe(function(_) {
								return provider.whenFinishedCurrentChanges();
							})
							.pipe(function(_) {
								return ComputeQueue.dumpJson(redis);
							})
							.pipe(function(_) {
								return InstancePool.toJson(redis)
									.then(function(jsondump :InstancePoolJson) {
										assertEquals(currentTargetNumberOfWorkers, jsondump.totalTargetInstances);
										assertEquals(jsondump.getTargetWorkerCount(provider.id), currentTargetNumberOfWorkers);
										assertCorrectWorkerCount(jsondump.getTargetWorkerCount(provider.id));
										return true;
									});
							});
					})
					//Now set a minimum number of machines
					.pipe(function(_) {
						currentTargetNumberOfWorkers = config.minWorkers = 1;
						return _workerProvider.updateConfig(config)
							.pipe(function(_) {
								return provider.whenFinishedCurrentChanges();
							})
							.thenWait(200)
							.pipe(function(_) {
								return InstancePool.toJson(redis)
									.then(function(jsondump :InstancePoolJson) {
										assertCorrectWorkerCount(jsondump.getTargetWorkerCount(provider.id));
										assertTrue(currentTargetNumberOfWorkers == jsondump.getMachines().length);
										assertTrue(jsondump.getTargetWorkerCount(provider.id) == currentTargetNumberOfWorkers);
										return true;
									});
							});
					})
					//Now add ten more jobs for a total of 10 jobs, and 4 workers (because the max is 4)
					.pipe(function(_) {
						var numJobs = 10;
						currentTargetNumberOfWorkers = Std.int(Math.min(Math.ceil(numJobs / MockWorkerProvider.CPUS_PER_WORKER), config.maxWorkers));
						var promises = [];
						var jobSubmitted = [];
						for (i in 0...numJobs) {
							var job = jobs[currentSubmittedJobIndex++];
							jobSubmitted.push(job);
							promises.push(ComputeQueue.enqueue(redis, job));
						}
						return Promise.whenAll(promises)
							.thenWait(50)
							.pipe(function(_) {
								return provider.whenFinishedCurrentChanges();
							})
							.pipe(function(_) {
								return InstancePool.toJson(redis)
									.then(function(jsondump :InstancePoolJson) {
										assertEquals(jsondump.getTargetWorkerCount(provider.id), currentTargetNumberOfWorkers);
										assertCorrectWorkerCount(jsondump.getTargetWorkerCount(provider.id));
										var jobMap = jsondump.getJobsForPool(provider.id);
										var machineIds = Set.createString(jobMap.array());
										assertEquals(machineIds.length(), 4);
										return true;
									});
							})
							//Then remove two jobs that are working on the same machine
							.pipe(function(_) {
								return InstancePool.toJson(redis)
									.pipe(function(jsondump :InstancePoolJson) {
										return Promise.whenAll(jsondump.getMachines()[0].jobs.map(function(computeJobId) {
											return ComputeQueue.removeComputeJob(redis, computeJobId);
										}));
									})
									.thenWait(20)
									.pipe(function(_) {
										return provider.whenFinishedCurrentChanges();
									})
									.pipe(function(_) {
										return InstancePool.toJson(redis);
									})
									.then(function(jsondump :InstancePoolJson) {
										assertEquals(jsondump.getTargetWorkerCount(provider.id), currentTargetNumberOfWorkers);
										assertCorrectWorkerCount(jsondump.getTargetWorkerCount(provider.id));
										var jobMap = jsondump.getJobsForPool(provider.id);
										var machineIds = Set.createString(jobMap.array());
										assertEquals(machineIds.length(), 4);
										return true;
									});
							})
							//Then remove ANOTHER two jobs that are working on the same machine
							.pipe(function(_) {
								currentTargetNumberOfWorkers--;
								return InstancePool.toJson(redis)
									.pipe(function(jsondump :InstancePoolJson) {
										return Promise.whenAll(jsondump.getMachines()[0].jobs.map(function(computeJobId) {
											return ComputeQueue.removeComputeJob(redis, computeJobId);
										}));
									})
									.thenWait(100)
									.pipe(function(_) {
										return provider.whenFinishedCurrentChanges();
									})
									.pipe(function(_) {
										return InstancePool.toJson(redis);
									})
									.then(function(jsondump :InstancePoolJson) {
										assertEquals(jsondump.getTargetWorkerCount(provider.id), currentTargetNumberOfWorkers);
										assertCorrectWorkerCount(jsondump.getTargetWorkerCount(provider.id));
										var jobMap = jsondump.getJobsForPool(provider.id);
										var machineIds = Set.createString(jobMap.array());
										assertEquals(machineIds.length(), currentTargetNumberOfWorkers);
										return true;
									});
							})
							//Now remove all jobs, there should be the minimum number of machines remaining
							.pipe(function(_) {
								currentTargetNumberOfWorkers = config.minWorkers;
								return InstancePool.toJson(redis)
									.pipe(function(jsondump :InstancePoolJson) {
										var promises = [];
										for (machine in jsondump.getMachines()) {
											if (machine.jobs != null) {
												for (computeJobId in machine.jobs) {
													promises.push(ComputeQueue.removeComputeJob(redis, computeJobId));
												}
											}
										}
										return Promise.whenAll(promises);
									})
									.thenWait(50)
									.pipe(function(_) {
										return provider.whenFinishedCurrentChanges();
									})
									.pipe(function(_) {
										return InstancePool.toJson(redis);
									})
									.then(function(jsondump :InstancePoolJson) {
										assertEquals(jsondump.getTargetWorkerCount(provider.id), currentTargetNumberOfWorkers);
										assertCorrectWorkerCount(jsondump.getTargetWorkerCount(provider.id));
										assertEquals(jsondump.getRunningMachines(provider.id).length, provider._currentWorkers.length());
										assertEquals(jsondump.getAvailableMachines(provider.id).length, currentTargetNumberOfWorkers);
										return true;
									});
							});
					})
					.thenTrue();
			});
	}
}