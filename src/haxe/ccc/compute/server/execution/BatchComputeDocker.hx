package ccc.compute.server.execution;

import haxe.remoting.JsonRpc;

import js.npm.RedisClient;
import js.npm.docker.Docker;

import ccc.docker.dataxfer.DockerDataTools;

import ccc.storage.*;

import util.DockerUrl;
import util.DockerTools;

typedef ExecuteJobResult = {
	var cancel :Void->Void;
	var promise :Promise<BatchJobResult>;
}

@:enum
abstract CleanupStep(String) to String from String {
	var CleanupStep_01_Remove_Container = 'CleanupStep_01_Remove_Container';
	var CleanupStep_02_Remove_Volumes = 'CleanupStep_02_Remove_Volumes';
	var CleanupStep_03_Remove_Input_Volume = 'CleanupStep_03_Remove_Input_Volume';
	var CleanupStep_04_Remove_Output_Volume = 'CleanupStep_04_Remove_Output_Volume';
	var CleanupStep_05_Complete = 'CleanupStep_05_Complete';
}

/**
 * Holds jobs waiting to be executed.
 */
class BatchComputeDocker
{
	/**
	 * This is the main method call when notified of a new job to be run.
	 * @param  streams   :LogStreams    [description]
	 * @return           [description]
	 */
	public static function executeJob(redis :RedisClient, job :DockerBatchComputeJob, dockerOpts:DockerConnectionOpts, fs :ServiceStorage, killContainer :Promise<Bool>, log :AbstractLogger) :ExecuteJobResult
	{
		Assert.notNull(redis);
		Assert.notNull(job);
		Assert.notNull(fs);

		var jobId = job.jobId;

		var jobStats :JobStats = redis;
		var jobStateTools :JobStateTools = redis;

		jobStats.jobDequeued(jobId);

		var docker = new Docker(dockerOpts);

		var parentLog = log;
		log = parentLog.child({jobId:jobId, step:'executing_job'});
		untyped log._level = parentLog._level;
		var containerId = null;

		log.info({});
		log.debug({log:'executeJob', job:LogTools.removePrivateKeys(job)});

		if (job.inputs == null) {
			job.inputs = [];
		}

		var containerInputsPath = job.containerInputsMountPath == null ? '/${DIRECTORY_INPUTS}' : job.containerInputsMountPath;
		var containerOutputsPath = job.containerOutputsMountPath == null ? '/${DIRECTORY_OUTPUTS}' : job.containerOutputsMountPath;

		//Create the various remote/local/worker storage services.
		var inputStorageRemote = fs.clone().appendToRootPath(job.inputDir());
		var outputStorageRemote = fs.clone().appendToRootPath(job.outputDir());
		var resultsStorageRemote = fs.clone().appendToRootPath(job.resultDir());


		var inputVolumeName = job.inputs.length > 0 ? JobTools.getWorkerVolumeNameInputs(jobId) : null;
		var outputVolumeName = JobTools.getWorkerVolumeNameOutputs(jobId);
		var outputsVolume :MountedDockerVolumeDef = {
			dockerOpts: dockerOpts,
			name: outputVolumeName,
		};

		// var killedPromise = new DeferredPromise();

		var copyInputs = copyInputsInternal.bind(job, dockerOpts, fs, redis, log);
		var copyOrCreateImage = copyOrCreateImageInternal.bind(job, docker, redis, log);
		var createOutputVolume = function() return DockerDataTools.createVolume(outputsVolume).thenTrue();
		var runContainer = runContainerInternal.bind(job, docker, redis, killContainer, log);
		var copyOutputs = copyOutputsInternal.bind(job, dockerOpts, fs, redis, log);
		var copyLogs = copyLogsInternal.bind(jobId, docker, resultsStorageRemote, redis, log);

		var killed = false;

		if (killContainer != null) {
			killContainer.then(function(isKilled) {
				if (isKilled) {
					killed = true;
				}
			}).catchError(function(err) {});
		}

		var eventStream :Stream<EventStreamItem> = null;
		eventStream = DockerTools.createEventStream(dockerOpts);
		//It is null if using the local docker daemon
		if (eventStream != null) {
			eventStream = eventStream
				.then(function(event) {
					if (event != null && containerId != null && event.id != null && event.id == containerId) {
						if (event.status == EventStreamItemStatus.kill) {
							log.warn('Container killed, perhaps the docker daemon was rebooted or crashed');
							// killedPromise.resolve(true);
							killed = true;
						}
					}
					return null;
				}).errorPipe(function(err) {
					log.error('error on event stream err=${Json.stringify(err)}');
					return Stream.stream(null);
				});
		}

		/*
			Set the job JobWorkingStatus. This is to
			resume the job in case the Node.js process
			crashes and is restarted.
		 */
		var jobWorkingStatus :JobWorkingStatus = null;
		var exitCode = -1;
		var outputFiles = [];
		var error :Dynamic;
		var copiedLogs = false;
		var timedOut = false;

		function cancel() {
			if (jobWorkingStatus == JobWorkingStatus.Cancelled) {
				return;
			}
			if (eventStream != null) {
				eventStream.end();
			}
			//This will break out of the chain below
			//There's no need to publish the job working status since it will be removed in the db after cancelling
			jobWorkingStatus = JobWorkingStatus.Cancelled;
			//TODO: proper cleanup
			//If the process is cancelled while in the middle of e.g. a large input file copy
			//the inputs files are not necessarily cleaned up.
			//The same applies to the docker image and container.
			//So there needs to be a reliable, resumable (after a crash) cleanup
			//process that gets rid of all job data/containers/images even
			//if the job was killed then the entire node.js process crashes.
			//We can live without this robustness for a *while* since workers are easily
			//created and destroyed, handling some of the cleanup for us.
			//This probably needs to happen in the Job objects where they can only change
			//state once the current state has returned a completed promise.
		}

		function setStatus(status :JobWorkingStatus) {
			if (status == JobWorkingStatus.Cancelled) {
				return Promise.promise(true);
			}
			if (status == JobWorkingStatus.Failed && jobWorkingStatus == JobWorkingStatus.Failed) {
				//Already failed
				return Promise.promise(true);
			}

			jobWorkingStatus = status;
			return jobStateTools.setWorkingStatus(jobId, status);
		}

		var p = Promise.promise(true)
			.pipe(function(_) {
				return jobStateTools.getWorkingStatus(jobId)
					.pipe(function(status) {
						if (status == null || status == JobWorkingStatus.None) {
							return setStatus(JobWorkingStatus.CopyingInputsAndImage);
						} else {
							jobWorkingStatus = status;
							return Promise.promise(true);
						}
					});
			})
			//Start doing the job stuff
			//Pipe logs to file streams
			//Copy the files to the remote worker
			.pipe(function(_) {
				if (jobWorkingStatus == JobWorkingStatus.CopyingInputsAndImage) {
					return Promise.whenAll([
							copyInputs().thenTrue(),
							copyOrCreateImage()
								.pipe(function(errorBlob) {
									if (errorBlob.error != null) {
										error = errorBlob.error;
										throw error;
									}
									return Promise.promise(true);
								}),
							createOutputVolume().thenTrue()
						])
						.pipe(function(_) {
							return setStatus(JobWorkingStatus.ContainerRunning);
						});
				} else {
					return Promise.promise(true);
				}
			})
			.pipe(function(_) {
				if (jobWorkingStatus == JobWorkingStatus.ContainerRunning) {
					return runContainer()
						.pipe(function(resultsBlob) {
							exitCode = resultsBlob.exitCode;
							error = resultsBlob.error;
							containerId = resultsBlob.containerId;
							timedOut = resultsBlob.timedOut;
							return setStatus(JobWorkingStatus.CopyingOutputsAndLogs);
						});
				} else {
					return Promise.promise(true);
				}
			})

			.pipe(function(_) {
				if (jobWorkingStatus == JobWorkingStatus.CopyingOutputsAndLogs) {
					return Promise.whenAll([
							copyOutputs()
								.then(function(outputFilesResult) {
									outputFiles = outputFilesResult;
									return true;
								}),
							copyLogs()
								.then(function(_) {
									copiedLogs = true;
									return true;
								})
						])
						.pipe(function(_) {
							return setStatus(JobWorkingStatus.FinishedWorking);
						});
				} else {
					return Promise.promise(true);
				}
			})
			.errorPipe(function(pipedError) {
				if (!killed) {
					log.error(pipedError);
				}
				error = error != null ? error : pipedError;
				return setStatus(JobWorkingStatus.Failed)
					.then(function(_) {
						return true;
					})
					.errorPipe(function(err) {
						log.error(err);
						return Promise.promise(true);
					});
			})
			.then(function(_) {
				var jobResult :BatchJobResult = {exitCode:exitCode, outputFiles:outputFiles, copiedLogs:copiedLogs, JobWorkingStatus:jobWorkingStatus, error:error, timeout:timedOut};
				if (!killed) {
					log.debug({message: 'job is complete, removing container out of band', jobResult:jobResult});
				}
				//The job is now finished. Clean up the temp worker storage,
				// out of the promise chain (for speed)

				log.debug({CleanupStep: CleanupStep.CleanupStep_01_Remove_Container});
				if (eventStream != null) {
					eventStream.end();
				}

				getContainer(docker, jobId)
					.pipe(function(containerData) {
						if (containerData != null) {
							return DockerPromises.removeContainer(docker.getContainer(containerData.Id), null, 'removeContainer jobId=$jobId')
								.then(function(_) {
									log.debug({CleanupStep: CleanupStep.CleanupStep_01_Remove_Container, success:true});
									return true;
								})
								.errorPipe(function(err) {
									log.error({CleanupStep: CleanupStep.CleanupStep_01_Remove_Container, error:Json.stringify(err)});
									return Promise.promise(false);
								});
						} else {
							return Promise.promise(true);
						}
					})
					.errorPipe(function(err) {
						log.error({CleanupStep: CleanupStep.CleanupStep_01_Remove_Container, error:Json.stringify(err)});
						return Promise.promise(true);
					})
					.pipe(function(_) {
						log.debug({CleanupStep: CleanupStep.CleanupStep_02_Remove_Volumes});
						return Promise.whenAll(
							[
								inputVolumeName == null ? Promise.promise(true) : DockerPromises.removeVolume(docker.getVolume(inputVolumeName))
									.then(function(_) {
										if (inputVolumeName != null) {
											log.debug({CleanupStep: CleanupStep.CleanupStep_03_Remove_Input_Volume, volume:inputVolumeName, success:true});
										} else {
											log.debug({CleanupStep: CleanupStep.CleanupStep_03_Remove_Input_Volume, volume:'none', success:true});
										}
										return true;
									})
									.errorPipe(function(err) {
										log.error({CleanupStep: CleanupStep.CleanupStep_03_Remove_Input_Volume, error:Json.stringify(err), success:false});
										return Promise.promise(false);
									}),
								DockerPromises.removeVolume(docker.getVolume(outputVolumeName))
									.then(function(_) {
										log.debug({CleanupStep: CleanupStep.CleanupStep_04_Remove_Output_Volume, volume:outputVolumeName, success:true});
										return true;
									})
									.errorPipe(function(err) {
										log.error({CleanupStep: CleanupStep.CleanupStep_04_Remove_Output_Volume, volume:outputVolumeName, error:Json.stringify(err), success:false});
										return Promise.promise(false);
									})
							])
							.thenTrue()
							.errorPipe(function(err) {
								log.error('Caught error on Promise.whenAll cleaning up volumes err=${Json.stringify(err)}');
								return Promise.promise(true);
							});
					})
					.then(function(_) {
						log.debug({CleanupStep: CleanupStep.CleanupStep_05_Complete, inputVolume:inputVolumeName, outputVolume:outputVolumeName});
						return true;
					});
				return jobResult;
			});

		return {promise:p, cancel:cancel};
	}

	static function getContainer(docker :Docker, jobId :JobId) :Promise<ContainerData>
	{
		return DockerPromises.listContainers(docker, {all:true, filters:DockerTools.createLabelFilter('jobId=$jobId')})
			.then(function(containers) {
				if (containers.length > 0) {
					return containers[0];
				} else {
					return null;
				}
			})
			.errorPipe(function(err) {
				Log.error('getContainer jobId=$jobId err=$err');
				return Promise.promise(null);
			});
	}

	static function copyInputsInternal(job :DockerBatchComputeJob, dockerOpts :DockerConnectionOpts, fs :ServiceStorage, redis :RedisClient, log :AbstractLogger) :Promise<Bool>
	{
		log = log.child({JobWorkingStatus:CopyingInputs});
		var jobId = job.jobId;
		var jobStats :JobStats = redis;
		if (job.inputsPath != null) {
			log.debug({log:'Reading from custom inputs path=' + job.inputsPath});
		}

		var inputStorageRemote = fs.clone().appendToRootPath(job.inputDir());
		var inputVolumeName = job.inputs.length > 0 ? JobTools.getWorkerVolumeNameInputs(jobId) : null;

		log.debug({log:'beginning input file processing'});
		return Promise.promise(true)
			// .pipe(function(_) {
			// 	log.debug({JobWorkingStatus:jobWorkingStatus, log:'Creating output volume'});
			// 	return DockerDataTools.createVolume(outputsVolume);
			// })
			.pipe(function(_) {
				log.debug({log:'copying ${job.inputs.length} inputs '});
				if (job.inputs.length == 0) {
					return Promise.promise(null);
				} else {
					var inputsVolume :MountedDockerVolumeDef = {
						dockerOpts: dockerOpts,
						name: inputVolumeName,
					};
					log.debug({log:'Creating volume=$inputVolumeName'});
					return DockerDataTools.createVolume(inputsVolume)
						.pipe(function(_) {
							log.debug({log:'Copying inputs to volume=$inputVolumeName'});
							return DockerJobTools.copyToVolume(inputStorageRemote, null, inputsVolume).end;
						});
				}
			})
			.then(function(_) {
				log.debug({log:'finished copying inputs=' + job.inputs});
				jobStats.jobCopiedInputs(jobId);
				return true;
			});
	}

	static function copyOrCreateImageInternal(job :DockerBatchComputeJob, docker :Docker, redis :RedisClient, log :AbstractLogger) :Promise<{error:Dynamic}>
	{
		log = log.child({JobWorkingStatus:CopyingImage});
		var jobId = job.jobId;
		log.debug('copyOrCreateImage ${jobId}');
		var jobStats :JobStats = redis;
		var error :Dynamic = null;
		//THIS NEEDS TO BE DONE IN **PARALLEL** with the copy inputs
		switch(job.image.type) {
			case Image:
				var dockerImage = job.image.value;
				var pull_options = job.image.pull_options != null ? job.image.pull_options : {};
				return ensureDockerImage(docker, dockerImage, log, pull_options)
					.errorPipe(function(err) {
						//Convert this error
						var jsonRpcError :ResponseError = {
							code: JsonRpcErrorCode.InvalidParams,
							message: JobSubmissionError.Docker_Image_Unknown,
							data: {
								docker_image_name: dockerImage,
								error: err
							}
						}
						log.error({error:jsonRpcError});
						error = jsonRpcError;
						return Promise.promise(true);
					})
					.then(function(_) {
						jobStats.jobCopiedImage(jobId);
						return {error:error};
					});
			case Context:
				var path = job.image.value;
				Assert.notNull(path, 'Context to build docker image is missing the local path');
				var localStorage = StorageTools.getStorage({type:StorageSourceType.Local, rootPath:path});
				var tag = jobId.dockerTag();
				return localStorage.readDir()
					.pipe(function(stream) {
						return DockerTools.buildDockerImage(docker, tag, stream, null, log.child({'level':30}));
					})
					.then(function(imageId) {
						log.debug({log:'Built image'});
						jobStats.jobCopiedImage(jobId);
						localStorage.close();//Not strictly necessary since it's local, but just always remember to do it
						return {error:error};
					});
		}
	}

	/**
	 * Workers never remove images, so once its here, it stays here.
	 * Plus calls to check images are costly when the aim is speed.
	 */
	static var CACHED_DOCKER_IMAGES = new Map<String, Bool>();
	public static function ensureDockerImage(docker :Docker, image :String, log :AbstractLogger, ?pull_options :Dynamic) :Promise<Bool>
	{
		if (CACHED_DOCKER_IMAGES.exists(image)) {
			return Promise.promise(true);
		} else {
			return DockerPromises.hasImage(docker, image)
				.pipe(function(imageExists) {
					if (imageExists) {
						log.debug({log:'Image exists=${image}'});
						CACHED_DOCKER_IMAGES.set(image, true);
						return Promise.promise(true);
					} else {
						pull_options = pull_options != null ? Reflect.copy(pull_options) : {};
						pull_options.fromImage = pull_options.fromImage != null ? pull_options.fromImage : image;
						log.debug({log:'Pulling docker image=${image}', pull_options:pull_options});
						return DockerTools.pullImage(docker, image, pull_options, log.child({'level':30}))
							.pipe(function(output) {
								//Ignoring output for now.
								log.debug({log:'Pulled docker image=${image}'});
								CACHED_DOCKER_IMAGES.set(image, true);
								return Promise.promise(true);
							});
					}
				});
		}
	}

	static function runContainerInternal(job :DockerBatchComputeJob, docker :Docker, redis :RedisClient, kill :Promise<Bool>, log :AbstractLogger) :Promise<{containerId:String,exitCode:Int,error:Dynamic, timedOut:Bool}>
	{
		var jobId = job.jobId;
		log = log.child({JobWorkingStatus:JobWorkingStatus.ContainerRunning});
		log.debug('runContainerInternal ${jobId}');
		var jobStats :JobStats = redis;

		var containerId :String = null;
		var exitCode :Int = -1;
		var error :Dynamic = null;
		var isTimedOut = false;
		/*
			First check if there is an existing container
			running, in case we crashed and resumed
		 */
		return getContainer(docker, jobId)
			.pipe(function(container) {
				if (container != null) {
					/* Container exists. Is it finished? */
					containerId = container.Id;
					log = log.child({container:containerId});
					log.debug({log:'Waiting on already running container=${containerId}'});
					var container = docker.getContainer(container.Id);
					return Promise.promise(container);
				} else {
					/*
						There is no existing container, so create one
						and run it
					 */
					var inputVolumeName = job.inputs.length > 0 ? JobTools.getWorkerVolumeNameInputs(jobId) : null;
					var outputVolumeName = JobTools.getWorkerVolumeNameOutputs(jobId);
					var containerInputsPath = job.containerInputsMountPath == null ? '/${DIRECTORY_INPUTS}' : job.containerInputsMountPath;
					var containerOutputsPath = job.containerOutputsMountPath == null ? '/${DIRECTORY_OUTPUTS}' : job.containerOutputsMountPath;

					var outputVolume = {
						Source: outputVolumeName,
						Destination: containerOutputsPath,
						Mode: 'rw',//https://docs.docker.com/engine/userguide/dockervolumes/#volume-labels
						RW: true
					};
					var mounts :Array<Mount> = [outputVolume];

					var inputVolume = null;
					if (inputVolumeName != null) {
						inputVolume = {
							Source: inputVolumeName,
							Destination: containerInputsPath,
							Mode: 'r',//https://docs.docker.com/engine/userguide/dockervolumes/#volume-labels
							RW: true
						};
						mounts.push(inputVolume);
					}

					var imageId = switch(job.image.type) {
						case Image:
							job.image.value;
						case Context:
							jobId;
					}

					var opts :CreateContainerOptions = job.image.optionsCreate;
					if (opts == null) {
						opts = {
							Image: null,//Set below
							AttachStdout: false,
							AttachStderr: false,
							Tty: false,
						}
					}

					opts.Cmd = opts.Cmd != null ? opts.Cmd : job.command;
					opts.WorkingDir = opts.WorkingDir != null ? opts.WorkingDir : job.workingDir;
					opts.HostConfig = opts.HostConfig != null ? opts.HostConfig : {};
					opts.HostConfig.LogConfig = {Type:DockerLoggingDriver.jsonfile, Config:{}};
					opts.HostConfig.Binds = opts.HostConfig.Binds != null ? opts.HostConfig.Binds : [];
					for (mount in mounts) {
						opts.HostConfig.Binds.push(mount.Source + ':' + mount.Destination + ':rw');
					}

					opts.Image = opts.Image != null ? opts.Image : imageId.toLowerCase();
					opts.Env = js.npm.redis.RedisLuaTools.isArrayObjectEmpty(opts.Env) ? [] : opts.Env;
					for (env in [
						'INPUTS=$containerInputsPath',
						'OUTPUTS=$containerOutputsPath',
						]) {
						opts.Env.push(env);
					}
					opts.Env.push('CCC_JOB_ID=$jobId');

					opts.Labels = opts.Labels != null ? opts.Labels : {};
					Reflect.setField(opts.Labels, 'jobId', jobId);

					Assert.notNull(docker);

					/**
					 * Can we mount the ccc server locally? This allows jobs to call the API.
					 * This can be a pretty big security hole, since it will essentially allow
					 * jobs to create unlimited jobs. Use at your own risk.
					 */
					if (job.mountApiServer == true) {
						opts.HostConfig.NetworkMode = 'container:${Constants.DOCKER_CONTAINER_NAME}';
					}

					log.debug({opts:opts});

					return DockerJobTools.runDockerContainer(docker, opts, null, null, kill, log)
						.then(function(containerunResult) {
							error = containerunResult.error;
							containerId = containerunResult != null && containerunResult.container != null ? containerunResult.container.id : null;
							log = log.child({container:containerId});
							return containerunResult != null ? containerunResult.container : null;
						});
				}
			})
			.pipe(function(container) {
				// log.debug('container=$containerId');
				if (container == null) {
					throw 'Missing container when attempting to run';
					return Promise.promise(true);
				} else {
					//Wait for the container to finish, but also monitor
					//the state of the job. If it becomes 'stopped'

					var promise = new DeferredPromise();


					var timeout :Int = job.parameters.maxDuration;
					if (timeout == null) {
						timeout = DEFAULT_MAX_JOB_TIME_MS;
					}
					var timeoutId = Node.setTimeout(function() {
						log.warn({message:'Timed out'});
						isTimedOut = true;
						if (promise != null) {
							promise.resolve(true);
							promise = null;
							container.kill(function(err,_) {});
						}
					}, timeout * 1000);

					promise.boundPromise
						.errorPipe(function(err) {
							return Promise.promise(true);
						})
						.then(function(_) {
							Node.clearTimeout(timeoutId);
						});

					DockerPromises.wait(container)
						.then(function(status :{StatusCode:Int}) {
							if (promise == null) {
								return;
							}
							exitCode = status.StatusCode;
							//This is caused by a job failure
							if (exitCode == 137) {
								error = "Job exitCode==137 this is caused by docker killing the container, likely on a restart.";
							}

							log.debug({exitcode:exitCode, error:error});
							if (error != null) {
								log.warn({exitcode:exitCode, error:error});
								// throw error;
							}
							jobStats.jobContainerExited(jobId, exitCode, error);
							promise.resolve(true);
							promise = null;
						})
						.catchError(function(err) {
							if (promise != null) {
								promise.boundPromise.reject(err);
							} else {
								log.error({error:err, message:'Caught error but container execution already resolved'});
							}
							promise = null;
						});

					return promise.boundPromise;
				}
			})
			.then(function(_) {
				return {containerId:containerId,exitCode:exitCode, error:error, timedOut:isTimedOut};
			});
	}

	static function copyOutputsInternal(job :DockerBatchComputeJob, dockerOpts :DockerConnectionOpts, fs :ServiceStorage, redis :RedisClient, log :AbstractLogger) :Promise<Array<String>>
	{
		var jobId = job.jobId;
		var jobStats :JobStats = redis;
		var outputVolumeName = JobTools.getWorkerVolumeNameOutputs(jobId);
		log = log.child({JobWorkingStatus:CopyingOutputs, outputVolumeName:outputVolumeName});
		log.debug({});
		if (job.outputsPath != null) {
			log.debug({log:'Writing to custom outputs path=' + job.outputsPath});
		}

		var outputStorageRemote = fs.clone().appendToRootPath(job.outputDir());

		var outputsVolume :MountedDockerVolumeDef = {
			dockerOpts: dockerOpts,
			name: outputVolumeName,
		};

		var outputFiles = [];

		return DockerDataTools.lsVolume(outputsVolume)
			.pipe(function(files) {
				outputFiles = files;
				if (outputFiles.length == 0) {
					return Promise.promise(true);
				} else {
					return DockerJobTools.copyFromVolume(outputStorageRemote, null, outputsVolume).end
						.thenTrue();
				}
			})
			.then(function(_) {
				jobStats.jobCopiedOutputs(jobId);
				return outputFiles;
			});
	}

	static function copyLogsInternal(jobId :JobId, docker :Docker, resultsStorageRemote :ServiceStorage, redis :RedisClient, log :AbstractLogger) :Promise<Bool>
	{
		var jobStats :JobStats = redis;
		return DockerJobTools.copyLogs(docker, jobId, resultsStorageRemote)
			.then(function(_) {
				jobStats.jobCopiedLogs(jobId);
				return true;
			});
	}
}