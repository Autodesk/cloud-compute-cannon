package ccc.compute.execution;

import util.DockerTools;

import haxe.Json;

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

		//Create the various remote/local/worker storage services.
		var inputStorageWorker = workerStorage.appendToRootPath(job.computeJobId.workerInputDir());
		var outputStorageWorker = workerStorage.appendToRootPath(job.computeJobId.workerOutputDir());
		var inputStorageRemote = fs.clone().appendToRootPath(job.item.inputDir());
		var outputStorageRemote = fs.clone().appendToRootPath(job.item.outputDir());
		var resultsStorageRemote = fs.clone().appendToRootPath(job.item.resultDir());

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
				log.info({JobWorkingStatus:jobWorkingStatus});
				if (jobWorkingStatus == JobWorkingStatus.CopyingInputs) {
					var inputStorage = fs.clone().appendToRootPath(job.item.inputDir());
					if (job.item.inputsPath != null) {
						log.debug({JobWorkingStatus:jobWorkingStatus, log:'Reading from custom inputs path=' + job.item.inputsPath});
					}

					log.debug({JobWorkingStatus:jobWorkingStatus, log:'beginning input file processing'});
					return Promise.promise(true)
						.pipe(function(_) {
							log.debug({JobWorkingStatus:jobWorkingStatus, log:'workerStorage.makeDir ${workerStorage.getRootPath()}${job.computeJobId.workerInputDir()}'});
							return inputStorageWorker.makeDir();
						})
						.pipe(function(_) {
							log.debug({JobWorkingStatus:jobWorkingStatus, log:'workerStorage.makeDir ${workerStorage.getRootPath()}${job.computeJobId.workerOutputDir()}'});
							return outputStorageWorker.makeDir()
								.then(function(_) {
									return true;
								});
						})
						.pipe(function(_) {
							log.debug({JobWorkingStatus:jobWorkingStatus, log:'copying inputs'});
							if (job.item.inputs == null) {
								job.item.inputs = [];
							}
							if (job.item.inputs.length == 0) {
								return Promise.promise(null);
							} else {
								log.debug({JobWorkingStatus:jobWorkingStatus, log:'Copying inputs from $inputStorageRemote to $inputStorageWorker items=${job.item.inputs}'});
#if debug
								return inputStorageRemote.listDir()
									.pipe(function(files) {
										log.debug({JobWorkingStatus:jobWorkingStatus, log:'Files in $inputStorageRemote=$files}'});
										return return DockerJobTools.copyFilesInternal(inputStorageRemote, inputStorageWorker, job.item.inputs);
									});
#else
								return DockerJobTools.copyFilesInternal(inputStorageRemote, inputStorageWorker, job.item.inputs);
#end
							}
						})
						.then(function(_) {
							// workerStorage.close();
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
				log.debug({JobWorkingStatus:jobWorkingStatus});
				if (jobWorkingStatus == JobWorkingStatus.CopyingImage) {
					//THIS NEEDS TO BE DONE IN **PARALLEL** with the copy inputs
					var promise = null;
					switch(job.item.image.type) {
						case Image:
							var docker = job.worker.getInstance().docker();
							var dockerImage = job.item.image.value;
							promise = DockerPromises.hasImage(docker, dockerImage)
								.pipe(function(imageExists) {
									if (imageExists) {
										log.debug({JobWorkingStatus:jobWorkingStatus, log:'Image exists=${dockerImage}'});
										return Promise.promise(true);
									} else {
										log.debug({JobWorkingStatus:jobWorkingStatus, log:'Pulling docker image=${dockerImage}'});
										return DockerTools.getImage(docker, {fromImage:dockerImage}, log.child({'level':30}));
									}
								});
						case Context:
							var path = job.item.image.value;
							Assert.notNull(path, 'Context to build docker image is missing the local path');
							var localStorage = StorageTools.getStorage({type:StorageSourceType.Local, rootPath:path});
							var docker = job.worker.getInstance().docker();
							var tag = job.id.dockerTag();
							promise = localStorage.readDir()
								.pipe(function(stream) {
									return DockerTools.buildDockerImage(docker, tag, stream, null, log.child({'level':30}));
								})
								.then(function(imageId) {
									log.debug({JobWorkingStatus:jobWorkingStatus, log:'Built image'});
									localStorage.close();//Not strictly necessary since it's local, but just always remember to do it
									return true;
								});
					}
					return promise
						.pipe(function(_) {
							return setStatus(JobWorkingStatus.ContainerRunning);
						});
				} else {
					return Promise.promise(true);
				}
			})
			.pipe(function(_) {
				log.debug({JobWorkingStatus:jobWorkingStatus});
				if (jobWorkingStatus == JobWorkingStatus.ContainerRunning) {
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
								var mounts :Array<Mount> = [
									{
										Source: DockerJobTools.getDockerHostMountablePath(inputStorageWorker.getRootPath()),
										Destination: '/${DIRECTORY_INPUTS}',
										Mode: 'rw',//https://docs.docker.com/engine/userguide/dockervolumes/#volume-labels
										RW: true
									},
									{
										Source: DockerJobTools.getDockerHostMountablePath(outputStorageWorker.getRootPath()),
										Destination: '/${DIRECTORY_OUTPUTS}',
										Mode: 'rw',//https://docs.docker.com/engine/userguide/dockervolumes/#volume-labels
										RW: true
									}
								];

								log.info({JobWorkingStatus:jobWorkingStatus, log:'Running container', mountInputs:'${mounts[0].Source}=>${mounts[0].Destination}', mountOutputs:'${mounts[1].Source}=>${mounts[1].Destination}'});

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
				log.info({JobWorkingStatus:jobWorkingStatus});
				if (jobWorkingStatus == JobWorkingStatus.CopyingOutputs) {
					// var outputStorage = fs.clone().appendToRootPath(job.item.outputDir());
					if (job.item.outputsPath != null) {
						log.debug({JobWorkingStatus:jobWorkingStatus, log:'Writing to custom outputs path=' + job.item.outputsPath});
					}
					// var workerOutputs = workerStorage.appendToRootPath(Path.join(job.computeJobId, DIRECTORY_OUTPUTS));
					// outputStorage = outputStorage.appendToRootPath(job.item.outputDir());
					// var workerOutputConfig :StorageDefinition = {
					// 	type: StorageSourceType.Sftp,
					// 	rootPath: job.computeJobId.workerOutputDir(),
					// 	sshConfig: job.worker.ssh
					// };
					// var source = StorageTools.getStorage(workerOutputConfig);
					return outputStorageWorker.listDir()
						.pipe(function(files) {
							outputFiles = files;
							//log.debug({JobWorkingStatus:jobWorkingStatus, log:'Copying outputs from $outputStorageWorker to $outputStorageRemote items=${files.join(", ")}'});
							if (outputFiles != null && outputFiles.length > 0) {
								return DockerJobTools.copyInternal(outputStorageWorker, outputStorageRemote);
							} else {
								return Promise.promise(true);
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
				log.info({JobWorkingStatus:jobWorkingStatus});
				if (jobWorkingStatus == JobWorkingStatus.CopyingLogs) {
					// var resultsStorage = fs.clone().appendToRootPath(job.item.resultDir());
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
				//The job is now finished. Clean up the temp worker storage,
				// out of the promise chain (for speed)
				inputStorageWorker.deleteDir()
					.pipe(function(_) {
						log.info('Deleted ${inputStorageWorker.toString()}');
						return outputStorageWorker.deleteDir();
					})
					.then(function(_) {
						log.info('Deleted ${outputStorageWorker.toString()}');
					})
					.catchError(function(err) {
						log.error('Problem deleting ${outputStorageWorker.toString()} or ${inputStorageWorker.toString()} err=${err}');
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
				Log.error('getContainerId err=$err');
				return Promise.promise(null);
			});
	}
}