package ccc.compute.server.execution;

import haxe.remoting.JsonRpc;

import js.npm.RedisClient;
import js.npm.docker.Docker;
import js.npm.tarstream.TarStream;

import ccc.docker.dataxfer.DockerDataTools;

import ccc.storage.*;

import util.DateFormatTools;
import util.DockerUrl;
import util.DockerTools;

typedef RunContainerResultTurbo = {
	var container :DockerContainer;
	var exitCode :Int;
	var error :Dynamic;
	var timedOut :Bool;
	var stderr :Array<String>;
	var stdout:Array<String>;
	var copyInputsTime :String;
	var containerExecutionTime :String;
	var containerCreateTime :String;
	var copyLogsTime :String;
	var containerExecutionStart :Date;
}

/**
 * Holds jobs waiting to be executed.
 */
class BatchComputeDockerTurbo
{
	public static function executeTurboJob(redis :RedisClient, job :BatchProcessRequestTurbo, docker :Docker, machineId :MachineId, log :AbstractLogger) :Promise<JobResultsTurbo>
	{
		Assert.notNull(job);
		var containerId = null;
		if (job.id == null) {
			job.id = js.npm.shortid.ShortId.generate();
		}
		var jobId = job.id;
		log = log.child({jobId:jobId, message:'TurboJob'});
		log.debug({});

		var turboJobs :TurboJobs = redis;
		var startTime = Date.now();
		var maxJobDurationSeconds = job.parameters != null && job.parameters.maxDuration != null ? job.parameters.maxDuration : TURBO_JOB_MAX_TIME_SECONDS_DEFAULT;
		turboJobs.jobStart(jobId, maxJobDurationSeconds, machineId);

		job.image = job.image != null ? job.image : (job.CreateContainerOptions != null ? job.CreateContainerOptions.Image : Constants.DOCKER_IMAGE_DEFAULT);

		var containerInputsPath = job.inputsPath == null ? '/${DIRECTORY_INPUTS}' : job.inputsPath;
		var containerOutputsPath = job.outputsPath == null ? '/${DIRECTORY_OUTPUTS}' : job.outputsPath;

		var ensureImage = BatchComputeDocker.ensureDockerImage.bind(docker, job.image, log, job.imagePullOptions);
		var runContainer = runContainerTurbo.bind(job, docker, log);
		var getOutputs = getOutputsTurbo2.bind(job, _, log);

		var resultBlob :RunContainerResultTurbo = null;
		var error :Dynamic;
		var outputFiles :DynamicAccess<String> = null;

		var stats :JobResultsTurboStats = {
			copyInputs: null,
			ensureImage: null,
			containerCreation: null,
			containerExecution: null,
			copyOutputs: null,
			copyLogs: null,
			total: null
		}

		return Promise.promise(true)
			//Start doing the job stuff
			//Pipe logs to file streams
			//Copy the files to the remote worker
			.pipe(function(_) {
				return ensureImage()
					.then(function(_) {
						stats.ensureImage = DateFormatTools.getShortStringOfDateDiff(startTime, Date.now());
						return true;
					});
			})
			.pipe(function(_) {
				var startTimeContainer = Date.now();
				return runContainer()
					.pipe(function(results) {
						log.trace({message:'container run finished', results:results});
						stats.containerExecution = DateFormatTools.getShortStringOfDateDiff(startTimeContainer, Date.now());
						stats.containerCreation = results.containerCreateTime;
						stats.copyLogs = results.copyLogsTime;
						stats.copyInputs = results.copyInputsTime;
						resultBlob = results;
						if (resultBlob.error != null) {
							log.warn({error:resultBlob.error, message: 'Error running container'});
						}
						error = resultBlob.error;

						function removeContainer() {
							if (results.container != null) {
								log.trace({message:'removing container'});
								DockerPromises.removeContainer(results.container, {force:true, v:true})
									.catchError(function(err) {
										log.warn({error:err, message:'Failed to remove container'});
									})
									.then(function(_) {
										log.trace({message:'removed container'});
										return true;
									});
							}
						}

						if (resultBlob != null && error == null && job.ignoreOutputs != true) {
							var startTimeOutputs = Date.now();
							log.trace({message:'Getting outputs'});
							return getOutputs(results.container)
								.then(function(files) {
									log.trace({message:'Got outputs'});
									stats.copyOutputs = DateFormatTools.getShortStringOfDateDiff(startTimeOutputs, Date.now());
									outputFiles = files;
									removeContainer();
									return true;
								});
						} else {
							removeContainer();
							stats.copyOutputs = '0';
							return Promise.promise(true);
						}
					});
			})
			.then(function(_) {
				var jobResultsFinal :JobResultsTurbo = {
					id: jobId,
					outputs: outputFiles,
					error: error,
					stdout: resultBlob != null ? resultBlob.stdout : [],
					stderr: resultBlob != null ? resultBlob.stderr : [],
					exitCode: resultBlob != null ? resultBlob.exitCode : -1,
					stats: stats
				};
				stats.total = DateFormatTools.getShortStringOfDateDiff(startTime, Date.now());
				turboJobs.jobEnd(jobId);
				log.trace({message:'Finished turbo job'});
				return jobResultsFinal;
			});
	}

	static function createTarStreamFromFiles(files :DynamicAccess<String>) :TarPack
	{
		var tarStream = TarStream.pack();
		for (fileName in files.keys()) {
			tarStream.entry({name: fileName}, files.get(fileName));
		}
		tarStream.finalize();
		return tarStream;
	}

	static function runContainerTurbo(job :BatchProcessRequestTurbo, docker :Docker, log :AbstractLogger) :Promise<RunContainerResultTurbo>
	{
		var jobId = job.id;

		var result :RunContainerResultTurbo = {
			container: null,
			exitCode: -1,
			error: null,
			timedOut: false,
			stdout: [],
			stderr: [],
			copyInputsTime: null,
			containerExecutionTime: null,
			containerCreateTime: null,
			copyLogsTime: null,
			containerExecutionStart: null,
		};

		var startTime = Date.now();

		/*
			First check if there is an existing container
			running, in case we crashed and resumed
		 */
		return Promise.promise(true)
			.pipe(function(_) {
				var containerInputsPath = job.inputsPath == null ? '/${DIRECTORY_INPUTS}' : job.inputsPath;
				var containerOutputsPath = job.outputsPath == null ? '/${DIRECTORY_OUTPUTS}' : job.outputsPath;

				var imageId = job.image;

				var opts :CreateContainerOptions = job.CreateContainerOptions != null ? job.CreateContainerOptions : { Image: imageId.toLowerCase()};
				opts.AttachStdout = false;
				opts.AttachStderr = false;
				opts.Tty = false;

				opts.Cmd = opts.Cmd != null ? opts.Cmd : job.command;
				opts.WorkingDir = opts.WorkingDir != null ? opts.WorkingDir : job.workingDir;
				opts.HostConfig = opts.HostConfig != null ? opts.HostConfig : {};
				opts.HostConfig.LogConfig = {Type:DockerLoggingDriver.jsonfile, Config:{}};

				opts.Image = opts.Image != null ? opts.Image : imageId.toLowerCase();
				opts.Env = js.npm.redis.RedisLuaTools.isArrayObjectEmpty(opts.Env) ? [] : opts.Env;
				for (env in [
					'INPUTS=$containerInputsPath',
					'OUTPUTS=$containerOutputsPath',
					]) {
					opts.Env.push(env);
				}

				opts.Labels = opts.Labels != null ? opts.Labels : {};
				Reflect.setField(opts.Labels, 'jobId', jobId);

				log.debug({opts:opts});

				var copyInputsOpts = {
					path: '/',
					noOverwriteDirNonDir: 'true'
				}

				var modifiedPathInputs :DynamicAccess<String> = null;
				if (job.inputs != null && job.inputs.keys().length > 0) {
					modifiedPathInputs = {};
					for (key in job.inputs.keys()) {
						modifiedPathInputs['$containerInputsPath/$key'] = Std.string(job.inputs[key]);
					}
				}

				var inputStream = modifiedPathInputs != null ? createTarStreamFromFiles(modifiedPathInputs) : null;

				return DockerJobTools.runDockerContainer(docker, opts, inputStream, inputStream != null ? copyInputsOpts : null, null, log)
					.then(function(containerunResult) {
						log.trace({message:'after DockerJobTools.runDockerContainer', result:containerunResult});
						result.error = containerunResult.error;
						result.copyInputsTime = containerunResult.copyInputsTime;
						result.container = containerunResult.container;
						result.containerExecutionStart = containerunResult.containerExecutionStart;
						result.containerCreateTime = containerunResult.containerCreateTime;
						log = log.child({container:result.container.id});
						return containerunResult != null ? containerunResult.container : null;
					});
			})
			.pipe(function(container) {
				if (container == null) {
					throw 'Missing container when attempting to run';
					return Promise.promise(true);
				} else if (result.error != null) {
					log.trace('Skipping containe.wait because there was an error in the run');
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
						result.timedOut = true;
						if (promise != null) {
							promise.resolve(true);
							promise = null;
							log.warn('Calling kill container ${container.id} because of a timeout');
							container.kill(function(err,_) {});
						}
					}, timeout * 1000);

					promise.boundPromise
						.errorPipe(function(err) {
							log.error({error:err, message:'Error on wait'});
							return Promise.promise(true);
						})
						.then(function(_) {
							Node.clearTimeout(timeoutId);
						});

					log.trace({message:'docker container wait'});
					DockerPromises.wait(container)
						.then(function(status :{StatusCode:Int}) {
							log.trace({message:'Returned from docker.wait', status:status});
							if (promise == null) {
								return;
							}
							result.exitCode = status.StatusCode;
							//This is caused by a job failure
							if (result.exitCode == 137) {
								result.error = "Job exitCode==137 this is caused by docker killing the container, likely on a restart.";
							}

							result.containerExecutionTime = DateFormatTools.getShortStringOfDateDiff(result.containerExecutionStart, Date.now());

							log.debug({exitcode:result.exitCode});
							if (result.error != null) {
								log.warn({exitcode:result.exitCode, error:result.error});
							}

							promise.resolve(true);
							promise = null;
						})
						.catchError(function(err) {
							log.error({error:err, message:'Error waiting for container to finish'});
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
			.pipe(function(_) {
				var getLogsStartTime = Date.now();
				if (result.container != null) {
					return DockerTools.getContainerLogs2(result.container)
						.then(function(stdOutErr) {
							result.copyLogsTime = DateFormatTools.getShortStringOfDateDiff(getLogsStartTime, Date.now());
							result.stdout = stdOutErr.stdout != null ? stdOutErr.stdout : result.stdout;
							result.stderr = stdOutErr.stderr != null ? stdOutErr.stderr : result.stderr;
							return true;
						})
						.errorPipe(function(err) {
							log.warn({error:err, mesage: 'Failed to get logs'});
							return Promise.promise(true);
						});
				} else {
					return Promise.promise(true);
				}
			})
			.then(function(_) {
				return result;
			});
	}

	static function getOutputsTurbo(job :BatchProcessRequestTurbo, docker :Docker, log :AbstractLogger) :Promise<{files:DynamicAccess<String>, disposed:Promise<Bool>}>
	{
		var jobId = job.id;
		var outputVolumeName = JobTools.getWorkerVolumeNameOutputs(jobId);

		var outputsVolume :MountedDockerVolumeDef = {
			docker: docker,
			name: outputVolumeName,
		};

		return DockerDataTools.getDataFiles(outputsVolume);
	}

	static function getOutputsTurbo2(job :BatchProcessRequestTurbo, container :DockerContainer, log :AbstractLogger) :Promise<DynamicAccess<String>>
	{
		var path = job.outputsPath != null ? job.outputsPath : '/${DIRECTORY_OUTPUTS}';
		return DockerDataTools.getDataFilesFromContainer(container, path)
			.errorPipe(function(err) {
				log.warn({error:err, f:'getOutputsTurbo2'});
				return Promise.promise(null);
			});
	}
}