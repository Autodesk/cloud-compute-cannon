package ccc.compute.server;

import haxe.Json;

import js.node.stream.Readable;
import js.node.stream.Writable;
import js.npm.RedisClient;
import js.npm.Docker;

import ccc.compute.ComputeQueue;
import ccc.compute.Definitions;
import ccc.compute.Definitions.Constants.*;
import ccc.compute.JobTools;
import ccc.storage.ServiceStorage;

import promhx.Promise;
import promhx.PromiseTools;
import promhx.StreamPromises;
import promhx.DockerPromises;
import promhx.CallbackPromise;
import promhx.StreamPromises;
import promhx.RequestPromises;

import util.DockerTools;
import util.DockerRegistryTools;

import t9.abstracts.net.*;

using Lambda;
using promhx.PromiseTools;
using StringTools;

/**
 * Server API methods
 */
class ServerCommands
{
	public static function buildImageIntoRegistry(imageStream :IReadable, repositoryTag :String, resultStream :IWritable) :Promise<DockerUrl>
	{
		trace('buildImageIntoRegistry');
		return Promise.promise(true)
			.pipe(function(_) {
				var docker = ConnectionToolsDocker.getDocker();
				return DockerTools.__buildDockerImage(docker, repositoryTag, imageStream, resultStream);
			})
			.pipe(function(_) {
				return pushImageIntoRegistryInternal(repositoryTag, resultStream);
			});
	}

	/**
	 * Will try to download the image if it doesn't exist.
	 * @param  image  :String          [description]
	 * @param  ?tag   :String          [description]
	 * @param  ?opts: PullImageOptions [description]
	 * @return        [description]
	 */
	public static function pushImageIntoRegistry(image :String, ?tag :String, ?opts: PullImageOptions) :Promise<DockerUrl>
	{
		var log = Logger.child({f:'pullImageIntoRegistry', image:image, tag:tag, opts:opts});
		var docker = ConnectionToolsDocker.getDocker();
		var registryAddress :Host = ConnectionToolsDocker.getLocalRegistryHost();//'$localDockerHost:5001';//TODO: find out the correct registry address
		// var opts :PullImageOptions = {};
		// if (username != null || password != null || auth != null || email != null || serveraddress != null) {
		// 	opts.authconfig = {
		// 		username: username,
		// 		password: password,
		// 		auth: auth,
		// 		email: email,
		// 		serveraddress: serveraddress
		// 	}
		// }

		var remoteImageUrl :DockerUrl = image;
		if (remoteImageUrl.tag == null) {
			remoteImageUrl.tag = 'latest';
		}
		var localImageUrl :DockerUrl = remoteImageUrl;
		if (tag != null) {
			localImageUrl.tag = tag;
		}
		log.debug({step:'start', message:'registryAddress=${registryAddress} remoteImageUrl=${remoteImageUrl} localImageUrl=${localImageUrl}'});

		return Promise.promise(true)
			.pipe(function(_) {
				return DockerRegistryTools.isImageIsRegistry(registryAddress, remoteImageUrl.repository, localImageUrl.tag);
			})
			.pipe(function(exists) {
				if (exists) {
					log.debug({step:'already_exists_in_registry'});
					localImageUrl.registryhost = ConnectionToolsRegistry.getRegistryAddress();
					return Promise.promise(localImageUrl);
				} else {
					log.debug({step:'does_not_exist'});
					return Promise.promise(true)
						//Pull image
						.pipe(function(_) {
							//Check if the image is in the local docker daemon
							return DockerPromises.listImages(docker)
								.pipe(function(imageData) {
									if (imageData.exists(function(id) {
										return id.RepoTags.has(localImageUrl);
									})) {
										log.debug({step:'exists_in_local_docker_daemon'});
										return Promise.promise(true);
									} else {
										log.debug({step:'does_not_exist_pulling'});
										return DockerTools.pullImage(docker, image, opts, null, 3, 100, log)
											.thenTrue();
									}
								});
						})
						.pipe(function(_) {
							return pushImageIntoRegistryInternal(image, tag);
						});
				}
			});
	}

	/**
	 * [pushImageIntoRegistry description]
	 * @param  image :String       Full docker image url.
	 * @param  ?tag  :String       If given, this tag replaces the tag in <repository>:<tag>
	 * @return       The full docker repository url, with the server address, so workers can use this from inside the CCC network. E.g. 192.168.4.3:5001/busybox:latest
	 */
	public static function pushImageIntoRegistryInternal(image :String, ?tag :String, ?resultStream :IWritable) :Promise<DockerUrl>
	{
		var log = Logger.child({f:'pushImageIntoRegistry', image:image, tag:tag});
		var docker = ConnectionToolsDocker.getDocker();
		var remoteImageUrl :DockerUrl = image;
		if (remoteImageUrl.tag == null) {
			remoteImageUrl.tag = 'latest';
		}
		trace('remoteImageUrl=${remoteImageUrl}');
		var localImageUrl :DockerUrl = remoteImageUrl;
		trace('localImageUrl=${localImageUrl}');
		if (tag != null) {
			localImageUrl.tag = tag;
		}
		trace('localImageUrl=${localImageUrl}');
		var registryAddress :Host = ConnectionToolsDocker.getLocalRegistryHost();

		return Promise.promise(true)
			//Tag image
			.pipe(function(_) {
				//Then tag it
				var dockerImage = docker.getImage(image);
				trace('fffff');
				trace('localImageUrl=${localImageUrl}');
				trace('Host.fromString("localhost:$REGISTRY_DEFAULT_PORT")=${Host.fromString('localhost:$REGISTRY_DEFAULT_PORT')}');
				localImageUrl.registryhost = Host.fromString('localhost:$REGISTRY_DEFAULT_PORT');
				trace('localImageUrl=${localImageUrl}');
				var newImageName = localImageUrl.noTag();
				trace('newImageName=${newImageName}');
				var promise = new CallbackPromise();
				log.debug({step:'pulled_success_tagging', repo:newImageName, tag:localImageUrl.tag});
				dockerImage.tag({repo:newImageName, tag:localImageUrl.tag}, promise.cb2);
				return promise
					.then(function(_) {
						log.debug({step:'tagged_now_pushing', repo:newImageName, tag:localImageUrl.tag});
						return localImageUrl;
					});
			})
			//push image
			.pipe(function(_) {
				return DockerTools.__pushImage(docker, localImageUrl, resultStream);
			})
			//Verify image in the registry
			.pipe(function(_) {
				log.debug({step:'pushed_now_verifying', repository:remoteImageUrl.repository, tag:localImageUrl.tag});
				return DockerRegistryTools.isImageIsRegistry(registryAddress, remoteImageUrl.repository, localImageUrl.tag)
					.then(function(exists) {
						log.debug({step:'verified', exists:exists, repository:remoteImageUrl.repository, tag:localImageUrl.tag});
						localImageUrl.registryhost = ConnectionToolsRegistry.getRegistryAddress();
						return localImageUrl;
					});
			});
	}

	public static function getJobStats(redis :RedisClient, jobId :JobId) :Promise<Stats>
	{
		return ComputeQueue.getJobStats(redis, jobId);
	}

	public static function removeJob(redis :RedisClient, fs :ServiceStorage, jobId :JobId) :Promise<String>
	{
		return ComputeQueue.getJob(redis, jobId)
			.pipe(function(jobdef :DockerJobDefinition) {
				if (jobdef == null) {
					return Promise.promise('unknown_job');
				} else {
					var promises = [JobTools.inputDir(jobdef), JobTools.outputDir(jobdef), JobTools.resultDir(jobdef)]
						.map(function(path) {
							return fs.deleteDir(path)
								.errorPipe(function(err) {
									Log.error({error:err, jobid:jobId, log:'Failed to remove ${path}'});
									return Promise.promise(true);
								});
						});
					return Promise.whenAll(promises)
						.pipe(function(_) {
							return ComputeQueue.removeJob(redis, jobId);
						})
						.then(function(_) {
							return 'removed $jobId';
						});
				}
			});
	}

	public static function killJob(redis :RedisClient, jobId :JobId) :Promise<String>
	{
		return ComputeQueue.getStatus(redis, jobId)
			.pipe(function(jobStatusBlob) {
				if (jobStatusBlob == null) {
					return Promise.promise('unknown_job');
				}
				return switch(jobStatusBlob.JobStatus) {
					case Pending,Working:
						if (jobStatusBlob.computeJobId != null) {
							// trace('ComputeQueue.finishComputeJob ${jobStatusBlob.computeJobId}');
							ComputeQueue.finishComputeJob(redis, jobStatusBlob.computeJobId, JobFinishedStatus.Killed)
								.then(function(_) {
									return 'killed';
								});
						} else {
							// trace('ComputeQueue.finishJob ${jobStatusBlob.jobId}');
							ComputeQueue.finishJob(redis, jobStatusBlob.jobId, JobFinishedStatus.Killed)
								.then(function(_) {
									return 'killed';
								});
						}
					case Finalizing,Finished:
						//Already finished
						Promise.promise('already_finished');
				}
			})
			.errorPipe(function(err) {
				return Promise.promise(Std.string(err));
			});
	}

	public static function getJobDefinition(redis :RedisClient, fs :ServiceStorage, jobId :JobId) :Promise<DockerJobDefinition>
	{
		Assert.notNull(redis);
		Assert.notNull(fs);
		Assert.notNull(jobId);
		return ComputeQueue.getJob(redis, jobId)
			.then(function(jobdef :DockerJobDefinition) {
				if (jobdef == null) {
					return null;
				} else {
					var jobDefCopy = Reflect.copy(jobdef);
					jobDefCopy.inputsPath = fs.getExternalUrl(JobTools.inputDir(jobdef));
					jobDefCopy.outputsPath = fs.getExternalUrl(JobTools.outputDir(jobdef));
					jobDefCopy.resultsPath = fs.getExternalUrl(JobTools.resultDir(jobdef));
					return jobDefCopy;
				}
				
				// var result :JobDescriptionComplete = {
				// 	definition: jobDefCopy,
				// 	status: status
				// }
				// trace('  result=$result');

				// var resultsJsonPath = JobTools.resultJsonPath(jobDefCopy);
				// return _fs.exists(resultsJsonPath)
				// 	.pipe(function(exists) {
				// 		if (exists) {
				// 			return _fs.readFile(resultsJsonPath)
				// 				.pipe(function(stream) {
				// 					if (stream != null) {
				// 						return StreamPromises.streamToString(stream)
				// 							.then(function(resultJsonString) {
				// 								result.result = Json.parse(resultJsonString);
				// 								return result;
				// 							});
				// 					} else {
				// 						return Promise.promise(result);
				// 					}
				// 				});
				// 		} else {
				// 			return Promise.promise(result);
				// 		}
			});
	}

	public static function getJobPath(redis :RedisClient, fs :ServiceStorage, jobId :JobId, pathType :JobPathType) :Promise<String>
	{
		return getJobDefinition(redis, fs, jobId)
			.then(function(jobdef :DockerJobDefinition) {
				if (jobdef == null) {
					Log.error({log:'jobId=$jobId no job definition, cannot get results path', jobid:jobId});
					return null;
				} else {
					return switch(pathType) {
						case Inputs: return jobdef.inputsPath;
						case Outputs: return jobdef.outputsPath;
						case Results: return jobdef.resultsPath;
						default:
							Log.error({log:'getJobPath jobId=$jobId unknown pathType=$pathType', jobid:jobId});
							throw 'getJobPath jobId=$jobId unknown pathType=$pathType';
					}
				}
			});
	}

	public static function getJobResults(redis :RedisClient, fs :ServiceStorage, jobId :JobId) :Promise<JobResult>
	{
		return getJobDefinition(redis, fs, jobId)
			.pipe(function(jobdef :DockerJobDefinition) {
				if (jobdef == null) {
					Log.error('jobId=$jobId no job definition, cannot get results path');
					return Promise.promise(null);
				} else {
					var resultsJsonPath = JobTools.resultJsonPath(jobdef);
					return fs.exists(resultsJsonPath)
						.pipe(function(exists) {
							if (exists) {
								return fs.readFile(resultsJsonPath)
									.pipe(function(stream) {
										if (stream != null) {
											return StreamPromises.streamToString(stream)
												.then(function(resultJsonString) {
													return Json.parse(resultJsonString);
												});
										} else {
											return Promise.promise(null);
										}
									});
							} else {
								return Promise.promise(null);
							}
						});
				}
			});
	}

	public static function getExitCode(redis :RedisClient, fs :ServiceStorage, jobId :JobId) :Promise<Null<Int>>
	{
		return getJobResults(redis, fs, jobId)
			.then(function(jobResults) {
				return jobResults != null ? jobResults.exitCode : null;
			});
	}

	public static function getStatus(redis :RedisClient, jobId :JobId) :Promise<Null<JobStatus>>
	{
		return ComputeQueue.getStatus(redis, jobId)
			.then(function(jobStatusBlob) {
				return jobStatusBlob != null ? jobStatusBlob.JobStatus : null;
			})
			.errorPipe(function(err) {
				Log.error(err);
				return Promise.promise(null);
			});
	}

	public static function getStdout(redis :RedisClient, fs :ServiceStorage, jobId :JobId) :Promise<String>
	{
		return getJobResults(redis, fs, jobId)
			.pipe(function(jobResults) {
				if (jobResults == null) {
					return Promise.promise(null);
				} else {
					var path = jobResults.stdout;
					trace('getStdout jobId=$jobId path=$path');
					if (path == null) {
						return Promise.promise(null);
					} else {
						return getPathAsString(path, fs);
					}
				}
			});
	}

	public static function getStderr(redis :RedisClient, fs :ServiceStorage, jobId :JobId) :Promise<String>
	{
		return getJobResults(redis, fs, jobId)
			.pipe(function(jobResults) {
				if (jobResults == null) {
					return Promise.promise(null);
				} else {
					var path = jobResults.stderr;
					if (path == null) {
						return Promise.promise(null);
					} else {
						return getPathAsString(path, fs);
					}
				}
			});
	}

	static function getPathAsString(path :String, fs :ServiceStorage) :Promise<String>
	{
		if (path.startsWith('http')) {
			return RequestPromises.get(path);
		} else {
			return fs.readFile(path)
				.pipe(function(stream) {
					return StreamPromises.streamToString(stream);
				});
		}
	}
}