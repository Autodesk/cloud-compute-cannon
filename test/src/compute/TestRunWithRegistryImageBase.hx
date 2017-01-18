package compute;

import js.npm.RedisClient;
import js.npm.fsextended.FsExtended;

import promhx.Promise;
import promhx.StreamPromises;

import ccc.compute.server.InstancePool;
import ccc.compute.server.ComputeQueue;
import ccc.compute.server.ComputeTools;
import ccc.compute.ConnectionToolsRedis;
import ccc.compute.execution.DockerJobTools;
import ccc.compute.execution.Jobs;
import ccc.compute.workers.WorkerManager;
import ccc.storage.ServiceStorageLocalFileSystem;
import ccc.storage.StorageSourceType;
import ccc.storage.ServiceStorage;
import ccc.storage.StorageDefinition;
import ccc.storage.StorageTools;

import utils.TestTools;

using promhx.PromiseTools;
using ccc.compute.server.InstancePool;
using ccc.compute.server.JobTools;
using ccc.compute.workers.WorkerProviderTools;
using ccc.compute.server.JobTools;
using StringTools;
using Lambda;

class TestRunWithRegistryImageBase extends TestComputeBase
{

	function runWithRegistryImage()
	{
		//Create 7 jobs and two machines each with 2 cpus
		//put all the jobs on the queue
		//consume them all
		//check the output

		var exampleBaseDir = 'test/res/exampleDockerBatchCompute';
		var sourceDockerContext = '$exampleBaseDir/dockerContext/';
		var inputDir = '$exampleBaseDir/inputs';

		// assume tester wants to user local file system if a service implementation isn't passed in
		if (jobOutputStorage == null) {
			var localStorageConfig :StorageDefinition = {
				type: StorageSourceType.Local,
				rootPath: ''
			};
			jobOutputStorage = StorageTools.getStorage(localStorageConfig);
		}

		var jobs = [];
		for (i in 0...1) {
			jobs.push(TestTools.createLocalJob('job$i-${ComputeTools.createUniqueId()}', sourceDockerContext, inputDir));
		}

		var manager = _workerManager;

		var redis = null;
		return Promise.promise(true)
			.pipe(function(_) {
				return ConnectionToolsRedis.getRedisClient()
					.then(function(r) {
						redis = r;
						return true;
					});
			})
			.pipe(function(_) {
				return jobOutputStorage.makeDir(jobOutputDirectory);
			})
			.then(function(_) {
				storageService = jobOutputStorage.appendToRootPath(jobOutputDirectory);
				_injector.unmap(ServiceStorage);
				_injector.map(ServiceStorage).toValue(storageService);
				return true;
			})

			.pipe(function(_) {
				return _workerProvider.setMaxWorkerCount(0);
			})

			.pipe(function(_) {
				return InstancePool.toJson(redis)
					.then(function(json :InstancePoolJson) {
						return true;
					});
			})

			.pipe(function(_) {
				//Make sure to put the inputs in the properly defined job path
				//TODO: this needs to be better documented or automated.
				var fsInputs = new ServiceStorageLocalFileSystem().setRootPath(exampleBaseDir + '/inputs');
				var promises = [];
				for (job in jobs) {
					var fsExampleInputs :ServiceStorage = storageService.clone();
					fsExampleInputs = fsExampleInputs.appendToRootPath(job.item.inputDir());
					// Log.info('Will copy job inputs to Storage Service with rootPath: ${fsExampleInputs.getRootPath()}');
					promises.push(DockerJobTools.copyInternal(fsInputs, fsExampleInputs));
				}
				return Promise.whenAll(promises);
			})

			.pipe(function(_) {
				return Promise.whenAll(jobs.map(function(job) {
					return ComputeQueue.enqueue(redis, job);
				}));
			})

			.pipe(function(_) {
				return ComputeQueue.toJson(redis)
					.then(function(jsondump :QueueJson) {
						assertEquals(jsondump.pending.length, jobs.length);
						return assertEquals(jsondump.working.length, 0);
					});
			})

			.pipe(function(_) {
				// Log.info('Setting max workers ${_workerProvider.id}=${numWorkers + 1}');
				return _workerProvider.setMaxWorkerCount(numWorkers + 1)
					.pipe(function(_) {
						return _workerProvider.whenFinishedCurrentChanges();
					});
			})

			.pipe(function(_) {
				// Log.info('Setting total worker count=$numWorkers');
				return InstancePool.setTotalWorkerCount(redis, numWorkers)
					.thenWait(50)
					.pipe(function(_) {
						return InstancePool.toJson(redis)
							.then(function(jsondump) {
								return true;
							});
					});

			})

			.pipe(function(_) {
				return TestTools.whenQueueisEmpty(redis);
			})

			.pipe(function(_) {
				return ComputeQueue.toJson(redis)
					.then(function(jsondump :QueueJson) {
						assertEquals(jsondump.pending.length, 0);
						return assertEquals(jsondump.working.length, 0);
					});
			})

			//Check stdout,err
			.pipe(function(_) {
				var promises = jobs.map(function(job) {

					var fsJobResults :ServiceStorage = storageService.clone();
					fsJobResults = fsJobResults.appendToRootPath(job.item.resultDir());

					return fsJobResults.readFile('stdout')
						.pipe(function(stdoutStream) {
							return StreamPromises.streamToString(stdoutStream)
								.then(function(stdout) {
									assertTrue(stdout.trim().endsWith('THIS IS STDOUT'));
									return true;
								});
						})
						.pipe(function(_) {
							return fsJobResults.readFile('stderr')
								.pipe(function(stderrStream) {
									return StreamPromises.streamToString(stderrStream)
										.then(function(stderr) {
											assertTrue(stderr.trim().endsWith('THIS IS STDERR'));
											return true;
										});
								});
						});
				});
				return Promise.whenAll(promises);
			})

			.thenTrue();
	}

	public function new() {}
}