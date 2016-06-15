package compute;

import js.npm.RedisClient;
import js.npm.FsExtended;

import promhx.Promise;
import promhx.StreamPromises;

import ccc.compute.InstancePool;
import ccc.compute.ComputeQueue;
import ccc.compute.ComputeTools;
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
using ccc.compute.InstancePool;
using ccc.compute.JobTools;
using ccc.compute.workers.WorkerProviderTools;
using ccc.compute.JobTools;
using StringTools;
using Lambda;

class TestCompleteJobSubmissionBase extends TestComputeBase
{
	private static var jobOutputDirectoryBase :String = 'tmp/completeJobSubmission/';

	private var dateString :String;
	private	var jobOutputDirectory :String;

	private var storageService :Null<ServiceStorage>;

	override public function setup() :Null<Promise<Bool>>
	{
		dateString = TestTools.getDateString();
		jobOutputDirectory = jobOutputDirectoryBase + dateString;
		return super.setup()
			.then(function(_) {
				_jobsManager = new Jobs();
				_injector.injectInto(_jobsManager);
				_workerManager = new WorkerManager();
				_injector.map(WorkerManager).toValue(_workerManager);
				_injector.injectInto(_workerManager);
				return true;
			});
	}

	// override public function tearDown() :Null<Promise<Bool>>
	// {
	// 	return super.tearDown()
	// 		.pipe(function (_) {
	// 			if (storageService != null) {
	// 				// storageService.resetRootPath();
	// 				Log.info('Job output cleanup: removing $jobOutputDirectory from ${storageService.getRootPath()}');
	// 				return storageService.deleteDir()
	// 				// return storageService.deleteDir(jobOutputDirectory)
	// 					// .pipe(function(_) {
	// 					// 	// Log.info('Job output cleanup: removing tmp/$DIRECTORY_NAME_WORKER_OUTPUT from ${storageService.getRootPath()}');
	// 					// 	return storageService.deleteDir('tmp/$DIRECTORY_NAME_WORKER_OUTPUT');
	// 					// });
	// 					;
	// 			} else {
	// 				Log.error("Job output cleanup failed; Storage Service reference is null.");
	// 				return Promise.promise(true);
	// 			}
	// 		});
	// }

	/**
	 * Follows a jobs (among others)
	 * as it is queued, worked on, and
	 * finished normally.
	 */
	function completeJobSubmission(?jobOutputStorage :ServiceStorage, numWorkers :Int = 2)
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