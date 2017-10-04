package ccc.compute.worker;

import js.npm.ssh2.Ssh;
import js.npm.ssh2.Ssh;

import ccc.docker.dataxfer.DockerDataTools;
import ccc.storage.ServiceStorage;
import ccc.storage.StorageTools;
import ccc.storage.StorageDefinition;
import ccc.storage.StorageSourceType;

import util.DateFormatTools;
import util.DockerTools;
import util.streams.StreamTools;

typedef WroteLogs = {
	var stdout :Bool;
	var stderr :Bool;
}

typedef RunDockerContainerResult = {
	var container :DockerContainer;
	var error :Dynamic;
	var copyInputsTime :String;
	var containerCreateTime :String;
	var containerExecutionStart :Date;
}

/**
 * This class manages the lifecycle of a single
 * batch compute running in a docker container
 * on a remote machine.
 *
 * It can be 'resumed' from the job state stored
 * in redis.
 *
 * It establishes direct ssh/wss connections to
 * the host machine
 */
class DockerJobTools
{
	/**
	 * This converts ServiceStorage copy operations into docker container 
	 * @param  storage     :ServiceStorage         [description]
	 * @param  storagePath :String                 [description]
	 * @param  volume      :MountedDockerVolumeDef [description]
	 * @return             [description]
	 */
	public static function copyToVolume(storage :ServiceStorage, storagePath :String, volume :MountedDockerVolumeDef) :CopyDataResult
	{
		switch(storage.type) {
			case Sftp: throw 'Not implemented yet: ServiceStorageSftp->Docker Volume';
			case PkgCloud: throw 'Not implemented yet: ServiceStoragePkgCloud->Docker Volume';
			case Local:
				var localStorage = cast(storage, ccc.storage.ServiceStorageLocalFileSystem);
				var localPath = localStorage.getPath(storagePath);
				return {end:DockerDataTools.transferDiskToVolume(localPath, volume)};
			case S3:
				var storageS3 = cast(storage, ccc.storage.ServiceStorageS3);
				var credentials = storageS3.getS3Credentials();
				credentials.path = storageS3.getPath(storagePath);
				return DockerDataTools.transferS3ToVolume(credentials, volume);
		}
	}

	public static function copyFromVolume(storage :ServiceStorage, storagePath :String, volume :MountedDockerVolumeDef) :CopyDataResult
	{
		switch(storage.type) {
			case Sftp: throw 'Not implemented yet: Docker Volume->ServiceStorageSftp';
			case PkgCloud: throw 'Not implemented yet: Docker Volume->ServiceStoragePkgCloud';
			case Local:
				var localStorage = cast(storage, ccc.storage.ServiceStorageLocalFileSystem);
				var localPath = localStorage.getPath(storagePath);
				return {end:DockerDataTools.transferVolumeToDisk(volume, localPath)};
			case S3:
				var storageS3 = cast(storage, ccc.storage.ServiceStorageS3);
				var credentials = storageS3.getS3Credentials();
				credentials.path = storageS3.getPath(storagePath);
				return DockerDataTools.transferVolumeToS3(volume, credentials);
		}
	}


	/**
	 * This is complicated and a PITA
	 * @param  path :String       [description]
	 * @return      [description]
	 */
	public static function getDockerHostMountablePath(path :String) :String
	{
		if (!path.startsWith(LOCAL_WORKER_HOST_MOUNT_PREFIX)) {
			return LOCAL_WORKER_HOST_MOUNT_PREFIX + path;
		} else {
			return path;
		}
	}

	public static function deleteJobRemoteData(job :DockerBatchComputeJob, fs :ServiceStorage) :Promise<Bool>
	{
		var paths = [
			JobTools.inputDir(job),
			JobTools.outputDir(job),
			JobTools.resultDir(job)
		].map(function(path) {
			return fs.deleteDir(path)
				.errorPipe(function(err) {
					Log.error({message:'Failed to delete $path for job=${job.jobId}', error:err});
					return Promise.promise(true);
				});
		});
		return Promise.whenAll(paths)
			.thenTrue();
	}

	/**
	 * Removes the container associated with a compute job.
	 * @param  job :QueueJobDefinition [description]
	 * @return     Docker container id
	 */
	public static function removeJobContainer(job :QueueJobDefinition<Dynamic>) :Promise<String>
	{
		Assert.notNull(job.id, 'job.id is null');
		throw "removeJobContainer cannot be done, docker stuff isn't known";
		// var docker = job.worker.getInstance().docker();
		// var docker = new Docker(job.worker.docker);
		// return removeContainer(docker, job.id, false);
		return Promise.promise("removeJobContainer cannot be done, docker stuff isn't known");
	}

	/**
	 * Copy inputs from a source ServiceStorage to the remove
	 * worker machine, where the worker file system is abstracted
	 * by a target ServiceStorage
	 * @param  source           :ServiceStorage      [description]
	 * @param  target           :ServiceStorage      [description]
	 * @param  ssh              :SshClient           [description]
	 * @param  inputs           :Array<FileResource> [description]
	 * @param  remoteInputsPath :String              [description]
	 * @return                  [description]
	 */
	public static function copyInputs(sourceDef :StorageDefinition, targetDef :StorageDefinition, inputs :Array<String>) :Promise<Dynamic>
	{
		if (inputs == null || inputs.length == 0) {
			return Promise.promise(true);
		}

		var source = StorageTools.getStorage(sourceDef);
		var target = StorageTools.getStorage(targetDef);

		return copyFilesInternal(source, target, inputs);
	}

	public static function copyFilesInternal(source :ServiceStorage, target :ServiceStorage, inputs :Array<String>) :Promise<Dynamic>
	{
		var promises = inputs.map(function(f) {
			return function() {
				return RetryPromise.retryDecayingInterval(function() {
					return source.readFile(f)
						.pipe(function(inputStream) {
							return target.writeFile(f, inputStream);
						});
					}, 8, 100, 'copying inputs=$inputs');
			}
		});
		//Copy one file at a time, not in parallel. This is because
		//I'm unsure that the sftp connection can handle multiple
		//file transfers, so this could be made more efficient in
		//the future.
		return PromiseTools.chainPipePromises(promises);
	}

	public static function copy(sourceDef :StorageDefinition, targetDef :StorageDefinition) :Promise<Dynamic>
	{
		var source = StorageTools.getStorage(sourceDef);
		var target = StorageTools.getStorage(targetDef);

		return Promise.promise(true)
			.pipe(function(_) {
				//Get the list of files
				return source.listDir();
			})
			.pipe(function(inputs) {
				return copyFilesInternal(source, target, inputs);
			});
	}

	public static function copyInternal(source :ServiceStorage, target :ServiceStorage) :Promise<Dynamic>
	{
		return source.listDir()
			.pipe(function(sourceFiles) {
				return copyFilesInternal(source, target, sourceFiles);
			});
	}

	//Build the docker image via the Docker API
	//Run the container, capturing outputs
	//On end, copy output files into storage
	//

	public static function runDockerContainer(docker :Docker, opts :CreateContainerOptions, inputs :IReadable, inputsOpts :Dynamic, kill :Promise<Bool>, log :AbstractLogger) :Promise<RunDockerContainerResult>
	{
		log = Logger.ensureLog(log, {image:opts.Image, jobId:opts.Labels.jobId, dockerhost:docker.modem.host});
		var result :RunDockerContainerResult = {
			container: null,
			error: null,
			copyInputsTime: null,
			containerCreateTime: null,
			containerExecutionStart: null
		};

		var startTime = Date.now();

		return Promise.promise(true)
			.pipe(function(_) {
				var promise = new DeferredPromise();
				log.trace({message:'createContainer', opts:opts});
				docker.createContainer(opts, function(createContainerError, container) {
					if (createContainerError != null) {
						log.error({log:'error_creating_container', opts:opts, error:createContainerError});
						promise.boundPromise.reject({dockerCreateContainerOpts:opts, error:createContainerError});
						return;
					}
					log.trace({message:'container created without error'});
					result.container = container;
					result.containerCreateTime = DateFormatTools.getShortStringOfDateDiff(startTime, Date.now());

					var finished = false;
					if (kill != null) {
						kill.then(function(ok) {
							log.trace({message:'container kill message received '});
							if (!finished) {
								log.trace({message:'container.kill()'});
								container.kill(function(err, data) {
									if (err != null) {
										log.trace({message:'container killed error', error:err});
									}
									log.trace({message:'container killed', data:data});
								});
							}
						});
					}
					promise.resolve(true);
				});
				return promise.boundPromise;
			})
			.pipe(function(_) {
				if (result.container == null || inputs == null) {
					result.copyInputsTime = '0';
					return Promise.promise(true);
				} else {
					var startInputCopyTime = Date.now();
					log.trace({message:'DockerPromises.copyIn start', inputsOpts:inputsOpts});
					return DockerPromises.copyIn(result.container, inputs, inputsOpts)
						.then(function(_) {
							log.trace({message:'DockerPromises.copyIn finished'});
							result.copyInputsTime = DateFormatTools.getShortStringOfDateDiff(startInputCopyTime, Date.now());
							return true;
						});
				}
			})
			.pipe(function(_) {
				if (result.container == null) {
					log.warn({message:'No container returned'});
					return Promise.promise(null);
				} else {
					var promise = new DeferredPromise();
					result.containerExecutionStart = Date.now();
					log.trace({message:'Starting container'});
					result.container.start(function(containerStartError, data) {
						log.trace({message:'Started container', error:containerStartError, data:data});
						if (containerStartError != null) {
							result.error = containerStartError;
							promise.resolve(result);
						} else {
							promise.resolve(result);
						}
					});
					return promise.boundPromise;
				}
			})
			.errorPipe(function(err :js.Error) {
				result.error = err;
				return Promise.promise(result);
			});
	}

	public static function getDockerResultStream(stream :js.node.stream.IReadable) :Promise<Array<String>>
	{
		var deferredPromise = new DeferredPromise();
		var result = [];
		stream.once(ReadableEvent.Close, function() {
			deferredPromise.resolve(result);
		});
		stream.once(ReadableEvent.End, function() {
			deferredPromise.resolve(result);
		});
		stream.once(ReadableEvent.Error, function(err) {
			deferredPromise.boundPromise.reject(err);
		});
		stream.on(ReadableEvent.Data, function(data) {
			var dataStream :ResponseStreamObject = Json.parse(data);
			if (dataStream.error == null) {
				result.push(dataStream.stream.trim());
			} else {
				deferredPromise.boundPromise.reject(dataStream);
			}
		});
		return deferredPromise.boundPromise;
	}

	public static function copyLogs(docker :Docker, jobId :JobId, fs :ServiceStorage, ?checkLogsReadable :Bool = true) :Promise<WroteLogs>
	{
		var result :WroteLogs = {stdout:false, stderr:false};
		return getContainerId(docker, jobId)
			.pipe(function(id) {
				if (id == null) {
					Log.error('Cannot find container with tag: "jobId=$jobId"');
					return Promise.promise(result);
				} else {
					var container = docker.getContainer(id);
					var promises = [
						DockerTools.getContainerStdout(container)
							.pipe(function(stream) {
								var passThrough = StreamTools.createTransformStream(
									function(data) {
										if (data != null) {
											result.stdout = true;
										}
										return data;
									});
								stream.pipe(passThrough);
								return fs.writeFile(STDOUT_FILE, passThrough)
									.pipe(function(_) {
										if (result.stdout) {
											//If there was data for the file,
											//check it exists before returning
											//since some systems e.g. S3 do not
											//return a file immediately
											return RetryPromise.retryRegular(function() {
												return fs.exists(STDOUT_FILE)
													.then(function(exists) {
														if (exists) {
															return true;
														} else {
															throw 'not yet found';
															return false;
														}
													});
											});
										} else {
											return Promise.promise(true);
										}
									});
							}),
						DockerTools.getContainerStderr(container)
							.pipe(function(stream) {
								var passThrough = StreamTools.createTransformStream(
									function(data) {
										if (data != null) {
											result.stderr = true;
										}
										return data;
									});
								stream.pipe(passThrough);
								return fs.writeFile(STDERR_FILE, passThrough)
									.pipe(function(_) {
										//If there was data for the file,
										//check it exists before returning
										//since some systems e.g. S3 do not
										//return a file immediately
										if (result.stderr) {
											return RetryPromise.retryRegular(function() {
												return fs.exists(STDERR_FILE)
													.then(function(exists) {
														if (exists) {
															return true;
														} else {
															throw 'not yet found';
															return false;
														}
													});
											}, 5, 500, 'get stderr', false);
										} else {
											return Promise.promise(true);
										}
									});
							})
					];

					//Do both streams concurrently
					return Promise.whenAll(promises)
						.then(function(_) {
							return result;
						});
				}
			});
	}

	public static function getContainerId(docker :Docker, jobId :JobId) :Promise<String>
	{
		return DockerPromises.listContainers(docker, {all:true, filters:DockerTools.createLabelFilter('jobId=$jobId')})
			.then(function(containers) {
				if (containers.length > 0) {
					return containers[0].Id;
				} else {
					Log.error({log:'Missing container id', jobId:jobId});
					DockerPromises.listContainers(docker, {all:true})
						.then(function(containers) {
							Log.error({log:'Missing container id', jobId:jobId});
						})
						.catchError(function(err) {/* This error is ignored */});
					return null;
				}
			})
			.errorPipe(function(err) {
				Log.error('getContainerId DockerPromises.listContainers jobId=$jobId error=${Json.stringify(err)}');
				return Promise.promise(null);
			});
	}

	public static function getContainer(docker :Docker, jobId :JobId) :Promise<DockerContainer>
	{
		return DockerPromises.listContainers(docker, {all:true, filters:DockerTools.createLabelFilter('jobId=$jobId')})
			.then(function(containers) {
				if (containers.length > 0) {
					return docker.getContainer(containers[0].Id);
				} else {
					Log.error({log:'Missing container id', jobId:jobId, dockerhost:docker.modem.host});
					return null;
				}
			})
			.errorPipe(function(err) {
				Log.error({log:'getContainer', error:err, jobId:jobId, dockerhost:docker.modem.host});
				return Promise.promise(null);
			});
	}

	public static function removeContainer(docker :Docker, jobId :JobId, ?suppressErrorIfContainerNotFound :Bool = false) :Promise<String>
	{
		return getContainerId(docker, jobId)
			.pipe(function(containerId) {
				if (containerId == null) {
					if (suppressErrorIfContainerNotFound) {
						return Promise.promise(null);
					} else {
						throw 'No container found for jobId=$jobId';
					}
				} else {
					return DockerTools.removeContainer(docker.getContainer(containerId), suppressErrorIfContainerNotFound)
						.then(function(_) {
							return containerId;
						});
				}
			});
	}
}