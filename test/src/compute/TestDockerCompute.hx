package compute;

using ccc.compute.server.workers.WorkerTools;

class TestDockerCompute extends TestComputeBase
{
	public static var ROOT_PATH = 'tmp/TestDockerCompute/';
	static var IMAGE_ID = 'testimage';
	var _worker :WorkerDefinition;

	public function new() {}

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
				var localProvider = new WorkerProviderBoot2Docker(config);
				_fs = ServiceStorageLocalFileSystem.getService(localProvider._localJobData);
				_workerProvider = localProvider;
				_worker = WorkerProviderBoot2Docker.getLocalDockerWorker();
				_injector.injectInto(_workerProvider);
				return _workerProvider.ready;
			});
	}

	@timeout(3000)
	public function testDockerConnectivity()
	{
		var workerDef = _worker;
		return Promise.promise(true)
			.pipe(function(_) {
				var docker = new Docker(workerDef.docker);
				var promise = new promhx.CallbackPromise();
				docker.info(promise.cb2);
				return promise;
			})
			.then(function(info :DockerInfo) {
				assertNotNull(Reflect.field(info, 'ID'));
				assertNotNull(Reflect.field(info, 'Containers'));
				return true;
			})
			.errorPipe(function(err) {
				Log.error(err);
				Log.error('Is the docker protocol set correctly? (http vs https)');
				throw err;
			})
			.thenTrue();
	}

	@timeout(500)
	public function testDockerCopyInputsLocal()
	{
		var dateString = TestTools.getDateString();
		var baseDir = '/tmp/testDockerCopyInputsLocal/$dateString';
		var sourceDir = '$baseDir/source';
		var destDir = '$baseDir/dest';

		FsExtended.ensureDirSync(sourceDir);
		FsExtended.ensureDirSync(destDir);

		var inputFileNameBase = 'input';
		var inputContentBase = 'This is some input';
		var inputFileCount = 3;
		for (i in 0...inputFileCount) {
			Fs.writeFileSync(Path.join(sourceDir, inputFileNameBase + i), inputContentBase + i);
		}

		var source = StorageTools.getStorage({type:StorageSourceType.Local, rootPath:sourceDir});
		var dest = StorageTools.getStorage({type:StorageSourceType.Local, rootPath:destDir});

		return DockerJobTools.copyInternal(source, dest)
			.pipe(function(_) {
				return dest.listDir();
			})
			.pipe(function(files) {
				for (i in 0...inputFileCount) {
					assertTrue(files.exists(function(f) return f == inputFileNameBase + i));
					var fullPath = Path.join(destDir, inputFileNameBase + i);
					assertEquals(Fs.readFileSync(fullPath, {encoding:'utf8'}), inputContentBase + i);
				}
				assertEquals(files.length, inputFileCount);
				FsExtended.deleteDirSync(Path.dirname(baseDir));
				return Promise.promise(true);
			});
	}

	@timeout(1000)
	public function UNSURE_SINCE_NO_MORE_LOCAL_SFTP_testDockerCopyInputsSftp()
	{
		var workerDef = _worker;
		var dateString = TestTools.getDateString();
		var baseDir = '/tmp/testDockerCopyInputsSftp/$dateString';
		var sourceDir = '$baseDir/source';
		var destDir = '$baseDir/dest';

		FsExtended.ensureDirSync(sourceDir);
		FsExtended.ensureDirSync(destDir);

		var inputFileNameBase = 'input';
		var inputContentBase = 'This is some input';
		var inputFileCount = 3;
		for (i in 0...inputFileCount) {
			Fs.writeFileSync(Path.join(sourceDir, inputFileNameBase + i), inputContentBase + i);
		}

		var source = StorageTools.getStorage({type:StorageSourceType.Local, rootPath:sourceDir});
		var dest = StorageTools.getStorage({type:StorageSourceType.Sftp, rootPath:destDir, credentials:workerDef.ssh});

		return DockerJobTools.copyInternal(source, dest)
			.pipe(function(_) {
				return dest.listDir();
			})
			.then(function(files) {
				for (i in 0...inputFileCount) {
					assertTrue(files.exists(function(f) return f == inputFileNameBase + i));
				}
				assertEquals(files.length, inputFileCount);
				return files;
			})
			.pipe(function(files) {
				files.sort(Reflect.compare);
				files.reverse();
				return Promise.whenAll(files.map(function(f) {
					return dest.readFile(f)
						.pipe(function(contentStream) {
							return StreamPromises.streamToString(contentStream);
						})
						.then(function(content) {
							var index = f.substr(f.length - 1);
							assertEquals(content, inputContentBase + index);
							return true;
						})
						.thenTrue()
						;
				}));
			})
			.then(function(_) {
				FsExtended.deleteDirSync(Path.dirname(baseDir));
				return true;
			})
			.thenTrue();
	}

	@timeout(240000)
	public function testBuildDockerJob()
	{
		var workerDef = _worker;

		var tarStream = js.npm.tarfs.TarFs.pack('test/res/testDockerImage1');

		var workerDef = _worker;
		var ssh;
		return Promise.promise(true)
			.pipe(function(_) {
				var docker = workerDef.getInstance().docker();
				return DockerTools.buildDockerImage(docker, IMAGE_ID, tarStream, null);
			})
			.thenTrue();
	}

	@timeout(240000)
	public function testRunDockerJob()
	{
		var workerDef = _worker;

		return Promise.promise(true)
			.pipe(function(_) {
				var docker = workerDef.getInstance().docker();
				var deferred = new DeferredPromise();
				docker.createContainer({
					Image: IMAGE_ID,
					AttachStdout: true,
					AttachStderr: true,
					Tty: false,
				}, function(err, container) {
					if (err != null) {
						deferred.boundPromise.reject(err);
						return;
					}

					container.attach({ logs:true, stream:true, stdout:true, stderr:true}, function(err, stream) {
						if (err != null) {
							deferred.boundPromise.reject(err);
							return;
						}
						container.start(function(err, data) {
							if (err != null) {
								deferred.boundPromise.reject(err);
								return;
							}
						});
						stream.once('end', function() {
							deferred.resolve(true);
						});
						stream.on('data', function(data) {
							Log.trace(data);
						});
					});
				});
				return deferred.boundPromise;
			})
			.thenTrue();
	}

	@timeout(240000)
	public function testCompleteDockerJobRun()
	{
		var dateString = TestTools.getDateString();
		var exampleBaseDir = 'test/res/exampleDockerBatchCompute';
		var sourceDockerContext = '$exampleBaseDir/dockerContext/';
		var inputDir = '$exampleBaseDir/inputs';
		var outputDir = 'tmp/testCompleteDockerJobRun/$dateString';

		var jobId :JobId = 'jobid1';
		var computeJobId :ComputeJobId = 'computeidjob1';

		var worker = WorkerProviderBoot2Docker.getLocalDockerWorker();

		var jobFsPath = 'tmp/testCompleteDockerJobRun/$dateString';

		var fs = ServiceStorageLocalFileSystem.getService().appendToRootPath(jobFsPath);
		// var workerStorage = _fs.appendToRootPath(jobFsPath);

		var redis :RedisClient = _injector.getValue(js.npm.RedisClient);
		var jobStats :JobStats = redis;

		var dockerJob :DockerJobDefinition = {
			jobId: jobId,
			computeJobId: computeJobId,
			worker: worker,
			image: {type:DockerImageSourceType.Context, value:sourceDockerContext, optionsBuild:{t:computeJobId}},
			inputs: FsExtended.listFilesSync(inputDir),
		};

		var job :QueueJobDefinitionDocker = {
			id: jobId,
			computeJobId: computeJobId,
			item: dockerJob,
			parameters: {cpus:1, maxDuration:1000},
			worker: worker
		}

		return Promise.promise(true)
			// .pipe(function(_) {
			// 	return workerStorage.deleteDir();
			// })
			.pipe(function(_) {
				//Make sure to put the inputs in the properly defined job path
				//TODO: this needs to be better documented or automated.
				var fsInputs = new ServiceStorageLocalFileSystem().setRootPath(exampleBaseDir + '/inputs');
				var fsExampleInputs = fs.clone().appendToRootPath(job.item.inputDir());
				return DockerJobTools.copyInternal(fsInputs, fsExampleInputs)
					.pipe(function(_) {
						return fsExampleInputs.listDir()
							.then(function(files) {
								return true;
							});
						});
			})
			.pipe(function(_) {
				return jobStats.jobEnqueued(job.id);
			})
			.pipe(function(_) {
				return BatchComputeDocker.executeJob(redis, job, fs, Log.log).promise;
			})
			.then(function(batchResults) {
				assertEquals(0, batchResults.exitCode);
				assertEquals(null, batchResults.error);
				return true;
			})
			.pipe(function(_) {
				var outputStorage = fs.appendToRootPath(job.item.outputDir());
				return outputStorage.listDir()
					.then(function(files) {
						return true;
					});
			})
			.thenTrue();
	}

	@timeout(60000)
	public function XtestDataInOutDataVolumeContainer()
	{
		var worker = WorkerProviderBoot2Docker.getLocalDockerWorker();
		var docker = new Docker(worker.docker);

		//Craete the local directory of files to copy
		var dateString = TestTools.getDateString();
		var baseInputsDir = '/tmp/testDataInOutDataVolumeContainer/$dateString/inputs/';
		var baseOutputsDir = '/tmp/testDataInOutDataVolumeContainer/$dateString/outputs/';
		FsExtended.ensureDirSync(baseInputsDir);
		FsExtended.ensureDirSync(baseOutputsDir);

		var input1Content = 'input1Content';
		var input2Content = 'input2Content';
		Fs.writeFileSync(baseInputsDir + 'input1', input1Content, {encoding:'utf8'});
		Fs.writeFileSync(baseInputsDir + 'input2', input2Content, {encoding:'utf8'});

		var name = 'testcontainer';
		var nameInputs = '${name}inputs';
		var nameOutputs = '${name}outputs';
		var image = 'tianon/true';//https://hub.docker.com/r/tianon/true/
		var label = 'testDataInOutDataVolumeContainer';
		var labels = {'testDataInOutDataVolumeContainer':'1'};

		var container1;
		var container2;

		function validateDirectory(dir) {
			var files = FsExtended.listFilesSync(dir);
			assertTrue(files.has('input1'));
			assertTrue(files.has('input2'));
			try {
				assertTrue(Fs.readFileSync(Path.join(dir, 'input1'), {encoding:'utf8'}) == input1Content);
				assertTrue(Fs.readFileSync(Path.join(dir, 'input2'), {encoding:'utf8'}) == input2Content);
			} catch(err :Dynamic) {
				assertTrue(false);
			}
		}

		return Promise.promise(true)
			//First cleanup existing
			.pipe(function(_) {
				return DockerTools.getContainersByLabel(docker, label)
					.pipe(function(containersData) {
						return Promise.whenAll(containersData.map(function(containerData) {
							return DockerPromises.removeContainer(docker.getContainer(containerData.Id), {v:true, force:true});
						}));
					});
			})
			.pipe(function(_) {
				assertNotNull(docker);
				assertNotNull(image);
				return DockerPromises.pull(docker, image);
			})
			//Create container inputs
			.pipe(function(_) {
				return DockerTools.createDataVolumeContainer(docker, nameInputs, image, ['/inputs'], labels)
					.then(function(container) {
						container1 = container;
						return true;
					});
			})
			//Create container outputs
			.pipe(function(_) {
				return DockerTools.createDataVolumeContainer(docker, nameOutputs, image, ['/outputs'], labels)
					.then(function(container) {
						container2 = container;
						return true;
					});
			})
			//Send created data to inputs container
			//and validate it by streaming it back
			.pipe(function(_) {
				return DockerTools.sendStreamToDataVolumeContainer(TarFs.pack(baseInputsDir), container1, '/inputs')
					.pipe(function(_) {
						//Now pipe it back out
						var tempDir = '/tmp/delete/' + TestTools.getDateString();
						FsExtended.ensureDirSync(tempDir);
						return DockerTools.getStreamFromDataVolumeContainer(container1, '/inputs')
							.pipe(function(stream) {
								return StreamPromises.pipe(stream, TarFs.extract(tempDir));
							})
							.then(function(_) {
								validateDirectory(tempDir + '/inputs');
								FsExtended.deleteDirSync(tempDir);
								FsExtended.deleteDirSync(baseInputsDir);
								FsExtended.deleteDirSync(baseOutputsDir);
								return true;
							});
					});
			})
			.thenTrue();
	}

	/**
	 * Jobs can specify a custom output path, rather than the default
	 * <ROOT>job/<JOB_ID>/inputs etc.
	 */
	@timeout(60000)
	public function XtestCustomOutputsPath()
	{
		var dateString = TestTools.getDateString();
		var basedir = 'tmp/testCustomOutputsPath/$dateString/';

		//This is the custom location where inputs and outputs will be stored
		//By default, jobs create a directory like:
		//<ROOT>/<JOB_ID>/...job data e.g. inputs/ and outputs/
		//However, you can also specify a custom input and output abstract FS
		var inputDir = 'inputsCUSTOM';
		var outputDir = 'outputsCUSTOM';
		var resultsDir = 'resultsCUSTOM';
		var inputDirLocalFull = Path.join(basedir, inputDir);
		var outputDirLocalFull = Path.join(basedir, outputDir);
		var resultsDirLocalFull = Path.join(basedir, resultsDir);
		FsExtended.ensureDirSync(inputDirLocalFull);
		FsExtended.ensureDirSync(outputDirLocalFull);

		var input1Name = 'foo';
		var input1Content = "sdfsdf";
		FsExtended.writeFileSync(Path.join(inputDirLocalFull, input1Name), input1Content);
		var output1Name = 'bar';
		var scriptName = 'script.sh';
		FsExtended.writeFileSync(Path.join(inputDirLocalFull, scriptName), '#!/usr/bin/env bash\ncat /${DIRECTORY_INPUTS}/foo > /${DIRECTORY_OUTPUTS}/bar');

		var jobId :JobId = 'jobid1';
		var computeJobId :ComputeJobId = 'computeidjob1';

		var worker = WorkerProviderBoot2Docker.getLocalDockerWorker();

		var fs = new ServiceStorageLocalFileSystem().setRootPath(basedir);
		var workerStorage = ServiceStorageLocalFileSystem.getService('$basedir/workerStorage');

		var redis :RedisClient = _injector.getValue(js.npm.RedisClient);

		var command = ['/bin/sh', '/${DIRECTORY_INPUTS}/$scriptName'];

		var dockerJob :DockerJobDefinition = {
			jobId: jobId,
			computeJobId: computeJobId,
			worker: worker,
			image: {type:DockerImageSourceType.Image, value:DOCKER_IMAGE_DEFAULT},
			inputs: FsExtended.listFilesSync(inputDirLocalFull),
			command: command,
			inputsPath: inputDir,
			outputsPath: outputDir,
			resultsPath: resultsDir
		};

		var job :QueueJobDefinitionDocker = {
			id: jobId,
			computeJobId: computeJobId,
			item: dockerJob,
			parameters: {cpus:1, maxDuration:1000},
			worker: worker
		}

		_streams = {out:js.Node.process.stdout, err:js.Node.process.stderr};
		return Promise.promise(true)
			.pipe(function(_) {
				return DockerJobTools.deleteWorkerInputs(job)
					.pipe(function(_) {
						return DockerJobTools.deleteWorkerOutputs(job);
					});
			})
			.pipe(function(_) {
				return BatchComputeDocker.executeJob(redis, job, fs, Logger.log).promise;
			})
			.errorPipe(function(err) {
				Log.error(err);
				return Promise.promise({exitCode:0, copiedLogs:false, outputFiles:[]});
			})
			.pipe(function(_) {
				return DockerJobTools.removeJobContainer(job);
			})
			.pipe(function(_) {
				var outputStorage = new ServiceStorageLocalFileSystem().setRootPath(outputDirLocalFull);
				return outputStorage.listDir()
					.then(function(files) {
						assertTrue(files.has(output1Name));
						assertEquals(FsExtended.readFileSync(Path.join(outputDirLocalFull, output1Name), {}), input1Content);
						return true;
					});
			})
			.pipe(function(_) {
				var resultsStorage = new ServiceStorageLocalFileSystem().setRootPath(resultsDirLocalFull);
				return resultsStorage.listDir()
					.then(function(files) {
						assertTrue(files.has('stdout'));
						assertTrue(files.has('stderr'));
						return true;
					});
			})
			.thenTrue();
	}
}