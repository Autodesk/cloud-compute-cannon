package ccc.compute.server;

import haxe.Resource;

import js.node.Fs;
import js.node.Path;
import js.node.stream.Readable;
import js.node.stream.Writable;
import js.npm.RedisClient;
import js.npm.docker.Docker;
import js.npm.redis.RedisLuaTools;

import ccc.compute.ComputeQueue;
import ccc.compute.InstancePool;
import ccc.compute.JobTools;
import ccc.compute.execution.DockerJobTools;
import ccc.compute.workers.WorkerTools;
import ccc.storage.ServiceStorage;

import promhx.PromiseTools;
import promhx.StreamPromises;
import promhx.DockerPromises;
import promhx.CallbackPromise;
import promhx.StreamPromises;
import promhx.RequestPromises;

import util.DockerTools;
import util.DockerUrl;
import util.DockerRegistryTools;
import util.DateFormatTools;

using promhx.PromiseTools;
using DateTools;

/**
 * Server API methods
 */
class ServerCommands
{
	/** For debugging */
	public static function traceStatus(redis :RedisClient) :Promise<Bool>
	{
		return status(redis)
			.then(function(statusBlob) {
				traceMagenta(Json.stringify(statusBlob, null, "  "));
				return true;
			});
	}

	public static function pending(redis :RedisClient) :Promise<Array<JobId>>
	{
		return ComputeQueue.toJson(redis)
			.then(function(out) {
				if(RedisLuaTools.isArrayObjectEmpty(out.pending)) {
					return [];
				} else {
					return out.pending;
				}
			});
	}

	public static function status(redis :RedisClient) :Promise<SystemStatus>
	{
		var workerJson :InstancePoolJson = null;
		var jobsJson :QueueJson = null;
		var workerJsonRaw :Dynamic = null;
		return Promise.promise(true)
			.pipe(function(_) {
				return Promise.whenAll(
					[
						InstancePool.toJson(redis)
							.then(function(out) {
								workerJson = out;
								return true;
							}),
						ComputeQueue.toJson(redis)
							.then(function(out) {
								jobsJson = out;
								return true;
							}),
						InstancePool.toRawJson(redis)
							.then(function(out) {
								workerJsonRaw = out;
								return true;
							})
					]);
			})
			.then(function(_) {
				var now = Date.now();

				var result = {
					pendingCount: jobsJson.pending.length,
					pendingTop5: jobsJson.pending.slice(0, 5),
					workers: workerJson.getMachines().map(function(m :JsonDumpInstance) {
						return {
							id :m.id,
							jobs: m.jobs != null ? m.jobs.map(function(computeJobId) {
								var jobId = jobsJson.getJobId(computeJobId);
								var stats = jobsJson.getStats(jobId);
								var enqueued = Date.fromTime(stats.enqueueTime);
								var dequeued = Date.fromTime(stats.lastDequeueTime);
								return {
									id: jobId,
									enqueued: enqueued.toString(),
									started: dequeued.toString(),
									duration: DateFormatTools.getShortStringOfDateDiff(dequeued, now)
								}
							}) : [],
							cpus: '${workerJson.getAvailableCpus(m.id)}/${workerJson.getTotalCpus(m.id)}'
						};
					}),
					finishedCount: jobsJson.getFinishedJobs().length,
					finishedTop5: jobsJson.getFinishedAndStatus(5),
					// workerJson: workerJson,
					// workerJsonRaw: workerJsonRaw
				};
				return result;
			})
			.pipe(function(result) {
				var promises = workerJson.getMachines().map(
					function(m) {
						return InstancePool.getWorker(redis, m.id)
							.pipe(function(workerDef) {
								if (workerDef.ssh != null) {
									return cloud.MachineMonitor.getDiskUsage(workerDef.ssh)
										.then(function(usage) {
											result.workers.iter(function(blob) {
												if (blob.id == m.id) {
													Reflect.setField(blob, 'disk', usage);
												}
											});
											return true;
										})
										.errorPipe(function(err) {
											Log.error({error:err, message:'Failed to get disk space for worker=${m.id}'});
											return Promise.promise(false);
										});
								} else {
									return Promise.promise(true);
								}
							});
					});
				return Promise.whenAll(promises)
					.then(function(_) {
						return result;
					});
			});
	}

	public static function version() :ServerVersionBlob
	{
		if (_versionBlob == null) {
			_versionBlob = versionInternal();
		}
		return _versionBlob;
	}

	static var _versionBlob :ServerVersionBlob;
	static function versionInternal()
	{
		var date = util.MacroUtils.compilationTime();
		var haxeCompilerVersion = Version.getHaxeCompilerVersion();
		var customVersion = null;
		try {
			customVersion = Fs.readFileSync('VERSION', {encoding:'utf8'});
		} catch(ignored :Dynamic) {
			customVersion = null;
		}
		var npmPackageVersion = null;
		try {
			npmPackageVersion = Json.parse(Resource.getString('package.json')).version;
		}
		var gitSha = null;
		try {
			gitSha = Version.getGitCommitHash().substr(0,8);
		} catch(e :Dynamic) {}

		//Single per instance id.
		var instanceVersion :String = null;
		try {
			instanceVersion = Fs.readFileSync('INSTANCE_VERSION', {encoding:'utf8'});
		} catch(ignored :Dynamic) {
			instanceVersion = js.npm.shortid.ShortId.generate();
			Fs.writeFileSync('INSTANCE_VERSION', instanceVersion, {encoding:'utf8'});
		}

		return {npm:npmPackageVersion, git:gitSha, compiler:haxeCompilerVersion, VERSION:customVersion, instance:instanceVersion, compile_time:date};
	}

	public static function serverReset(redis :RedisClient, fs :ServiceStorage) :Promise<Bool>
	{
		return return ComputeQueue.getAllJobIds(redis)
			.pipe(function(jobIds :Array<JobId>) {
				return Promise.whenAll(jobIds.map(function(jobId) {
					return ComputeQueue.getJob(redis, jobId)
						.pipe(function(job :DockerJobDefinition) {
							return DockerJobTools.deleteJobRemoteData(job, fs);
						});
				}));
			})
			.pipe(function(_) {
				return hardStopAndDeleteAllJobs(redis);
			});
	}

	public static function hardStopAndDeleteAllJobs(redis :RedisClient) :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				//Remove all jobs
				return ComputeQueue.getAllJobIds(redis)
					.pipe(function(jobIds) {
						return Promise.whenAll(jobIds.map(function(jobId) {
							return ComputeQueue.removeJob(redis, jobId);
						}));
					})
					//Clean all workers
					.pipe(function(_) {
						return ccc.compute.InstancePool.getAllWorkers(redis)
							.pipe(function(workerDefs) {
								return Promise.whenAll(workerDefs.map(
									function(instance) {
										return WorkerTools.cleanWorker(instance);
									}));
							});
					});
			})
			.thenTrue();
	}

	public static function buildImageIntoRegistry(imageStream :IReadable, repositoryTag :String, resultStream :IWritable) :Promise<DockerUrl>
	{
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
									log.debug({imageData:imageData});
									if (imageData.exists(function(id) {
										return id != null && id.RepoTags != null && id.RepoTags.has(localImageUrl);
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
		var localImageUrl :DockerUrl = remoteImageUrl;
		if (tag != null) {
			localImageUrl.tag = tag;
		}
		var registryAddress :Host = ConnectionToolsDocker.getLocalRegistryHost();

		return Promise.promise(true)
			//Tag image
			.pipe(function(_) {
				//Then tag it
				var dockerImage = docker.getImage(image);
				localImageUrl.registryhost = Host.fromString('localhost:$REGISTRY_DEFAULT_PORT');
				var newImageName = localImageUrl.noTag();
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

	public static function removeJobComplete(redis :RedisClient, fs :ServiceStorage, jobId :JobId, ?removeFiles :Bool = true) :Promise<String>
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
							ComputeQueue.finishComputeJob(redis, jobStatusBlob.computeJobId, JobFinishedStatus.Killed)
								.then(function(_) {
									return 'killed';
								});
						} else {
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

	public static function getJobDefinition(redis :RedisClient, fs :ServiceStorage, jobId :JobId, ?externalUrl :Bool = true) :Promise<DockerJobDefinition>
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
					jobDefCopy.inputsPath = externalUrl ? fs.getExternalUrl(JobTools.inputDir(jobdef)) : JobTools.inputDir(jobdef);
					jobDefCopy.outputsPath = externalUrl ? fs.getExternalUrl(JobTools.outputDir(jobdef)) : JobTools.outputDir(jobdef);
					jobDefCopy.resultsPath = externalUrl ? fs.getExternalUrl(JobTools.resultDir(jobdef)) : JobTools.resultDir(jobdef);
					return jobDefCopy;
				}
			});
	}

	public static function getJobPath(redis :RedisClient, fs :ServiceStorage, jobId :JobId, pathType :JobPathType) :Promise<String>
	{
		return getJobDefinition(redis, fs, jobId, false)
			.then(function(jobdef :DockerJobDefinition) {
				if (jobdef == null) {
					Log.error({log:'jobId=$jobId no job definition, cannot get results path', jobid:jobId});
					return null;
				} else {
					var path = switch(pathType) {
						case Inputs: jobdef.inputsPath;
						case Outputs: jobdef.outputsPath;
						case Results: jobdef.resultsPath;
						default:
							Log.error({log:'getJobPath jobId=$jobId unknown pathType=$pathType', jobid:jobId});
							throw 'getJobPath jobId=$jobId unknown pathType=$pathType';
					}
					return fs.getExternalUrl(path);
				}
			});
	}

	public static function getJobResults(redis :RedisClient, fs :ServiceStorage, jobId :JobId) :Promise<JobResult>
	{
		return getJobDefinition(redis, fs, jobId, false)
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

	public static function getStatus(redis :RedisClient, jobId :JobId) :Promise<Null<String>>
	{
		return ComputeQueue.getJobStatus(redis, jobId)
			.then(function(jobStatusBlob) {
				var s :String = jobStatusBlob.status == JobStatus.Working ? jobStatusBlob.statusWorking : jobStatusBlob.status;
				return s;
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