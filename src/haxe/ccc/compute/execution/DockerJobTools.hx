package ccc.compute.execution;

import util.DockerTools;

import haxe.Json;

import js.Error;
import js.Node;
import js.node.stream.Readable;
import js.node.Path;
import js.npm.Docker;
import js.npm.Ssh;
import js.npm.Ssh;

import promhx.Promise;
import promhx.PromiseTools;
import promhx.RetryPromise;
import promhx.deferred.DeferredPromise;
import promhx.DockerPromises;
import promhx.StreamPromises;

import ccc.storage.ServiceStorage;
import ccc.storage.StorageTools;
import ccc.storage.StorageDefinition;
import ccc.storage.StorageSourceType;
import ccc.compute.ComputeTools;
import ccc.compute.ComputeQueue;

using ccc.compute.JobTools;
using ccc.compute.workers.WorkerTools;
using StringTools;
using promhx.PromiseTools;

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

	public static function deleteJobRemoteData(job :DockerJobDefinition, fs :ServiceStorage) :Promise<Bool>
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

	public static function deleteWorkerInputs(job :QueueJobDefinitionDocker) :Promise<Bool>
	{
		var workerStorage = getWorkerStorage(job);
		return workerStorage.deleteDir(job.computeJobId.workerInputDir())
			.errorPipe(function(err) {
				Log.error(err);
				return Promise.promise(true);
			})
			.then(function(_) {
				workerStorage.close();
				return true;
			});
	}

	public static function deleteWorkerOutputs(job :QueueJobDefinitionDocker) :Promise<Bool>
	{
		var workerStorage = getWorkerStorage(job);
		return workerStorage.deleteDir(job.computeJobId.workerOutputDir())
			.errorPipe(function(err) {
				Log.error(err);
				return Promise.promise(true);
			})
			.then(function(_) {
				workerStorage.close();
				return true;
			});
	}

	static function getWorkerStorage(job :QueueJobDefinitionDocker) :ServiceStorage
	{
		Assert.notNull(job.computeJobId, 'job.computeJobId is null');
		var workerStorageConfig :StorageDefinition = {
			type: StorageSourceType.Sftp,
			rootPath: WORKER_JOB_DATA_DIRECTORY_HOST_MOUNT,
			sshConfig: job.worker.ssh
		};
		return StorageTools.getStorage(workerStorageConfig);
	}

	public static function getContainerFromJob(job :QueueJobDefinitionDocker) :Promise<DockerContainer>
	{
		Assert.notNull(job.computeJobId, 'job.computeJobId is null');
		var docker = job.worker.getInstance().docker();
		return getContainer(docker, job.computeJobId);
	}

	/**
	 * Removes the container associated with a compute job.
	 * @param  job :QueueJobDefinitionDocker [description]
	 * @return     Docker container id
	 */
	public static function removeJobContainer(job :QueueJobDefinitionDocker) :Promise<String>
	{
		Assert.notNull(job.computeJobId, 'job.computeJobId is null');
		var docker = job.worker.getInstance().docker();
		return removeContainer(docker, job.computeJobId, false);
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
				return RetryPromise.pollDecayingInterval(function() {
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

	public static function runDockerContainer(docker :Docker, computeJobId :ComputeJobId, imageId :String, cmd :Array<String>, mounts :Array<Mount>, workingDir :String, labels :Dynamic<String>, log :AbstractLogger) :Promise<{container:DockerContainer,error:Dynamic}>
	{
		log = Logger.ensureLog(log, {image:imageId, computejobid:computeJobId, dockerhost:docker.modem.host});
		log.info({log:'run_docker_container', cmd:'[${cmd != null ? cmd.join(",") : ''}]', mounts:'[${mounts != null ? mounts.join(",") : ''}]', workingDir:workingDir, labels:labels});
		var promise = new DeferredPromise();
		imageId = imageId.toLowerCase();
		Assert.notNull(docker);
		Assert.notNull(imageId);
		var hostConfig :CreateContainerHostConfig = {};
		hostConfig.Binds = [];
		//Ensure json-file logging so we can get to the logs
		hostConfig.LogConfig = {Type:DockerLoggingDriver.jsonfile, Config:{}};
		for (mount in mounts) {
			hostConfig.Binds.push(mount.Source + ':' + mount.Destination + ':rw');
		}

		var opts :CreateContainerOptions = {
			Image: imageId,
			Cmd: cmd,
			AttachStdout: true,
			AttachStderr: true,
			Tty: false,
			Labels: labels,
			HostConfig: hostConfig,
			WorkingDir: workingDir
		}
		log.debug({log:'run_docker_container', opts:opts});
		docker.createContainer(opts, function(createContainerError, container) {
			if (createContainerError != null) {
				log.error({log:'error_creating_container', opts:opts, error:createContainerError});
				promise.boundPromise.reject({dockerCreateContainerOpts:opts, error:createContainerError});
				return;
			}

			container.start(function(containerStartError, data) {
				if (containerStartError != null) {
					var result = {container:container, error:containerStartError};
					promise.resolve(result);
					return;
				}
				container.wait(function(waitError, endResult) {
					var result = {container:container, error:waitError};
					promise.resolve(result);
				});
			});
		});
		return promise.boundPromise;
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

	public static function copyLogs(docker :Docker, computeJobId :ComputeJobId, fs :ServiceStorage) :Promise<Bool>
	{
		return getContainerId(docker, computeJobId)
			.pipe(function(id) {
				if (id == null) {
					Log.error('Cannot find container with tag: "computeId=$computeJobId"');
					return Promise.promise(false);
				} else {
					return Promise.whenAll([fs.getFileWritable(STDOUT_FILE), fs.getFileWritable(STDERR_FILE)])
						.pipe(function(pipes) {
							var out = pipes[0];
							var err = pipes[1];
							return DockerTools.writeContainerLogs(docker.getContainer(id), out, err);
						})
						//TODO: am I not listening to the correct events?
						.thenWait(100);
				}
			});
	}

	public static function getContainerId(docker :Docker, computeJobId :ComputeJobId) :Promise<String>
	{
		return DockerPromises.listContainers(docker, {all:true, filters:DockerTools.createLabelFilter('computeId=$computeJobId')})
			.then(function(containers) {
				if (containers.length > 0) {
					return containers[0].Id;
				} else {
					Log.error({log:'Missing container id', computejobid:computeJobId});
					DockerPromises.listContainers(docker, {all:true})
						.then(function(containers) {
							Log.error({log:'Missing container id', computejobid:computeJobId});
						});
					return null;
				}
			})
			.errorPipe(function(err) {
				Log.error({log:'getContainerId', computejobid:computeJobId, error:err});
				return Promise.promise(null);
			});
	}

	public static function getContainer(docker :Docker, computeJobId :ComputeJobId) :Promise<DockerContainer>
	{
		return DockerPromises.listContainers(docker, {all:true, filters:DockerTools.createLabelFilter('computeId=$computeJobId')})
			.then(function(containers) {
				if (containers.length > 0) {
					return docker.getContainer(containers[0].Id);
				} else {
					Log.error({log:'Missing container id', computejobid:computeJobId, dockerhost:docker.modem.host});
					return null;
				}
			})
			.errorPipe(function(err) {
				Log.error({log:'getContainer', error:err, computejobid:computeJobId, dockerhost:docker.modem.host});
				return Promise.promise(null);
			});
	}

	public static function removeContainer(docker :Docker, computeJobId :ComputeJobId, ?suppressErrorIfContainerNotFound :Bool = false) :Promise<String>
	{
		return getContainerId(docker, computeJobId)
			.pipe(function(containerId) {
				if (containerId == null) {
					if (suppressErrorIfContainerNotFound) {
						return Promise.promise(null);
					} else {
						throw 'No container found for computeJobId=$computeJobId';
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