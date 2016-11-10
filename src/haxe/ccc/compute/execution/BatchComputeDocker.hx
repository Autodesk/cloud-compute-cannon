package ccc.compute.execution;

import util.DockerTools;

import haxe.Json;
import haxe.remoting.JsonRpc;

import js.Node;
import js.node.Path;

import js.npm.RedisClient;
import js.npm.docker.Docker;

import promhx.Promise;
import promhx.Stream;
import promhx.deferred.DeferredStream;
import promhx.deferred.DeferredPromise;
import promhx.DockerPromises;
import promhx.RequestPromises;

import ccc.compute.ComputeTools;
import ccc.compute.ComputeQueue;
import ccc.compute.InstancePool;
import ccc.compute.LogStreams;
import ccc.compute.execution.DockerJobTools;

import ccc.docker.dataxfer.DockerDataTools;

import ccc.storage.StorageTools;
import ccc.storage.ServiceStorage;
import ccc.storage.StorageDefinition;
import ccc.storage.StorageSourceType;

import util.DockerUrl;

using ccc.compute.JobTools;
using ccc.compute.workers.WorkerTools;

using promhx.PromiseTools;
using Lambda;

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
	 * @param  computeId :ComputeJobId  [description]
	 * @param  streams   :LogStreams    [description]
	 * @return           [description]
	 */
	public static function executeJob(redis :RedisClient, job :QueueJobDefinitionDocker, fs :ServiceStorage, workerStorage :ServiceStorage, log :AbstractLogger) :ExecuteJobResult
	{
		Assert.notNull(job);
		Assert.notNull(fs);
		Assert.notNull(workerStorage);
		Assert.notNull(job.computeJobId);

		var parentLog = log;
		log = parentLog.child({jobId:job.id, computejobid:job.computeJobId, step:'executing_job'});
		untyped log._level = parentLog._level;

		// log.info({log:'executeJob', fs:fs, workerStorage:workerStorage, job:LogTools.removePrivateKeys(job)});
		log.info({log:'executeJob', job:LogTools.removePrivateKeys(job)});

		var computeJobId = job.computeJobId;
		var docker = job.worker.getInstance().docker();

		if (job.item.inputs == null) {
			job.item.inputs = [];
		}

		//Create the various remote/local/worker storage services.
		var inputStorageWorker = workerStorage.appendToRootPath(job.computeJobId.workerInputDir());
		var outputStorageWorker = workerStorage.appendToRootPath(job.computeJobId.workerOutputDir());
		var inputStorageRemote = fs.clone().appendToRootPath(job.item.inputDir());
		var outputStorageRemote = fs.clone().appendToRootPath(job.item.outputDir());
		var resultsStorageRemote = fs.clone().appendToRootPath(job.item.resultDir());

		var inputVolumeName = job.item.inputs.length > 0 ? JobTools.getWorkerVolumeNameInputs(job.computeJobId) : null;
		var outputVolumeName = JobTools.getWorkerVolumeNameOutputs(job.computeJobId);
		var outputsVolume :MountedDockerVolumeDef = {
			dockerOpts: job.worker.docker,
			name: outputVolumeName,
		};

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

		function cancel() {
			if (jobWorkingStatus == JobWorkingStatus.Cancelled) {
				return;
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
			var promise = ComputeQueue.setComputeJobWorkingStatus(redis, computeJobId, jobWorkingStatus)
				.thenTrue();
			//Is anyone listening to this?
			promise.then(function(_) {
				redis.publish(job.id, Json.stringify({jobId:job.id, JobWorkingStatus:status}));
			});
			return promise;
		}

		var p = Promise.promise(true)
			.pipe(function(_) {
				return ComputeQueue.getComputeJobWorkingStatus(redis, computeJobId)
					.pipe(function(status) {
						if (status == null) {
							return setStatus(JobWorkingStatus.CopyingInputs);
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
				if (jobWorkingStatus == JobWorkingStatus.CopyingInputs) {
					log.info({JobWorkingStatus:jobWorkingStatus});
					if (job.item.inputsPath != null) {
						log.debug({JobWorkingStatus:jobWorkingStatus, log:'Reading from custom inputs path=' + job.item.inputsPath});
					}

					log.debug({JobWorkingStatus:jobWorkingStatus, log:'beginning input file processing'});
					return Promise.promise(true)
						.pipe(function(_) {
							log.debug({JobWorkingStatus:jobWorkingStatus, log:'Creating output volume'});
							return DockerDataTools.createVolume(outputsVolume);
						})
						.pipe(function(_) {
							log.debug({JobWorkingStatus:jobWorkingStatus, log:'copying ${job.item.inputs.length} inputs '});
							if (job.item.inputs.length == 0) {
								return Promise.promise(null);
							} else {
								var inputsVolume :MountedDockerVolumeDef = {
									dockerOpts: job.worker.docker,
									name: inputVolumeName,
								};
								log.debug({JobWorkingStatus:jobWorkingStatus, log:'Creating volume=$inputVolumeName'});
								return DockerDataTools.createVolume(inputsVolume)
									.pipe(function(_) {
										log.debug({JobWorkingStatus:jobWorkingStatus, log:'Copying inputs to volume=$inputVolumeName'});
										return DockerJobTools.copyToVolume(inputStorageRemote, null, inputsVolume).end;
									});
							}
						})
						.then(function(_) {
							log.debug({JobWorkingStatus:jobWorkingStatus, log:'finished copying inputs=' + job.item.inputs});
							return true;
						})
						.pipe(function(_) {
							return setStatus(JobWorkingStatus.CopyingImage);
						});
					} else {
						return Promise.promise(true);
					}
			})
			.pipe(function(_) {
				if (jobWorkingStatus == JobWorkingStatus.CopyingImage) {
					log.debug({JobWorkingStatus:jobWorkingStatus});
					//THIS NEEDS TO BE DONE IN **PARALLEL** with the copy inputs
					switch(job.item.image.type) {
						case Image:
							var docker = job.worker.getInstance().docker();
							var dockerImage = job.item.image.value;
							return DockerPromises.hasImage(docker, dockerImage)
								.pipe(function(imageExists) {
									if (imageExists) {
										log.debug({JobWorkingStatus:jobWorkingStatus, log:'Image exists=${dockerImage}'});
										return setStatus(JobWorkingStatus.ContainerRunning);
									} else {
										var pull_options = job.item.image.pull_options != null ? job.item.image.pull_options : {};
										pull_options.fromImage = pull_options.fromImage != null ? pull_options.fromImage : dockerImage;
										log.debug({JobWorkingStatus:jobWorkingStatus, log:'Pulling docker image=${dockerImage}', pull_options:pull_options});
										return DockerTools.pullImage(docker, dockerImage, pull_options, log.child({'level':30}))
											.pipe(function(output) {
												//Ignoring output for now.
												return setStatus(JobWorkingStatus.ContainerRunning);
											})
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
												return setStatus(JobWorkingStatus.Failed);
											});
									}
								});
						case Context:
							var path = job.item.image.value;
							Assert.notNull(path, 'Context to build docker image is missing the local path');
							var localStorage = StorageTools.getStorage({type:StorageSourceType.Local, rootPath:path});
							var docker = job.worker.getInstance().docker();
							var tag = job.id.dockerTag();
							return localStorage.readDir()
								.pipe(function(stream) {
									return DockerTools.buildDockerImage(docker, tag, stream, null, log.child({'level':30}));
								})
								.pipe(function(imageId) {
									log.debug({JobWorkingStatus:jobWorkingStatus, log:'Built image'});
									localStorage.close();//Not strictly necessary since it's local, but just always remember to do it
									return setStatus(JobWorkingStatus.ContainerRunning);
								});
					}
				} else {
					return Promise.promise(true);
				}
			})
			.pipe(function(_) {
				if (jobWorkingStatus == JobWorkingStatus.ContainerRunning) {
					log.debug({JobWorkingStatus:jobWorkingStatus});
					/*
						First check if there is an existing container
						running, in case we crashed and resumed
					 */
					return getContainer(docker, computeJobId)
						.pipe(function(container) {
							if (container != null) {
								/* Container exists. Is it finished? */
								log.info({JobWorkingStatus:jobWorkingStatus, log:'Waiting on already running container=${container.Id}'});
								var container = docker.getContainer(container.Id);
								return DockerPromises.wait(container)
									.pipe(function(status :{StatusCode:Int}) {
										exitCode = status.StatusCode;
										return setStatus(JobWorkingStatus.CopyingOutputs);
									});
							} else {
								/*
									There is no existing container, so create one
									and run it
								 */
								var outputVolume = {
									Source: outputVolumeName,
									Destination: '/${DIRECTORY_OUTPUTS}',
									Mode: 'rw',//https://docs.docker.com/engine/userguide/dockervolumes/#volume-labels
									RW: true
								};
								var mounts :Array<Mount> = [outputVolume];

								var inputVolume = null;
								if (inputVolumeName != null) {
									inputVolume = {
										Source: inputVolumeName,
										Destination: '/${DIRECTORY_INPUTS}',
										Mode: 'r',//https://docs.docker.com/engine/userguide/dockervolumes/#volume-labels
										RW: true
									};
									mounts.push(inputVolume);
								}

								log.info({JobWorkingStatus:jobWorkingStatus, log:'Running container', mountInputs:(inputVolume != null ? '${inputVolume.Source}=>${inputVolume.Destination}' : null), mountOutputs:'${outputVolume.Source}=>${outputVolume.Destination}'});

								var labels :Dynamic<String> = {
									jobId: job.id,
									computeId: job.computeJobId
								}
								var imageId = switch(job.item.image.type) {
									case Image:
										job.item.image.value;
									case Context:
										job.id;
								}

								return DockerJobTools.runDockerContainer(docker, job.computeJobId, imageId, job.item.command, mounts, job.item.workingDir, labels, log)
									.pipe(function(containerunResult) {
										error = containerunResult.error;
										return DockerPromises.wait(containerunResult.container)
											.then(function(status :{StatusCode:Int}) {
												exitCode = status.StatusCode;
												log.info({JobWorkingStatus:jobWorkingStatus, exitcode:exitCode});
												if (error != null) {
													log.error({JobWorkingStatus:jobWorkingStatus, exitcode:exitCode, error:error});
													throw error;
												}
												return true;
											})
											.pipe(function(_) {
												return setStatus(JobWorkingStatus.CopyingOutputs);
											});
									});
							}
						});
				} else {
					return Promise.promise(true);
				}
			})
			// This part will have to be broken up so compute job watching can be resumed
			.pipe(function(_) {
				if (jobWorkingStatus == JobWorkingStatus.CopyingOutputs) {
					log.info({JobWorkingStatus:jobWorkingStatus});
					// var outputStorage = fs.clone().appendToRootPath(job.item.outputDir());
					if (job.item.outputsPath != null) {
						log.debug({JobWorkingStatus:jobWorkingStatus, log:'Writing to custom outputs path=' + job.item.outputsPath});
					}

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
						.pipe(function(_) {
							return setStatus(JobWorkingStatus.CopyingLogs);
						});
				} else {
					return Promise.promise(true);
				}
			})
			.pipe(function(_) {
				if (jobWorkingStatus == JobWorkingStatus.CopyingLogs) {
					log.info({JobWorkingStatus:jobWorkingStatus});
					log.info('Copying logs from to $resultsStorageRemote');
					return DockerJobTools.copyLogs(docker, job.computeJobId, resultsStorageRemote)
						.pipe(function(_) {
							copiedLogs = true;
							return setStatus(JobWorkingStatus.FinishedWorking);
						});
				} else {
					return Promise.promise(true);
				}
			})
			.errorPipe(function(pipedError) {
				traceYellow("CAUGHT THROWN ERROR " + pipedError);
				error = pipedError;
				log.error(pipedError);
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
				var jobResult :BatchJobResult = {exitCode:exitCode, outputFiles:outputFiles, copiedLogs:copiedLogs, JobWorkingStatus:jobWorkingStatus, error:error};
				log.info({message: 'job is complete, removing container out of band', jobResult:jobResult});
				//The job is now finished. Clean up the temp worker storage,
				// out of the promise chain (for speed)

				log.debug({CleanupStep: CleanupStep.CleanupStep_01_Remove_Container});

				getContainer(docker, computeJobId)
					.pipe(function(containerData) {
						if (containerData != null) {
							return DockerPromises.removeContainer(docker.getContainer(containerData.Id), null, 'removeContainer computeJobId=$computeJobId')
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

	static function getContainer(docker :Docker, computeJobId :ComputeJobId) :Promise<ContainerData>
	{
		return DockerPromises.listContainers(docker, {all:true, filters:DockerTools.createLabelFilter('computeId=$computeJobId')})
			.then(function(containers) {
				if (containers.length > 0) {
					return containers[0];
				} else {
					return null;
				}
			})
			.errorPipe(function(err) {
				Log.error('getContainer computeJobId=$computeJobId err=$err');
				return Promise.promise(null);
			});
	}
}