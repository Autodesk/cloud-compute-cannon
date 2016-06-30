package ccc.compute.execution;

/**
 * Represents a running job in a docker container.
 * Actively monitors the job.
 * TODO: Also can resume
 */

import util.DockerTools;

import haxe.Json;

import js.Node;
import js.npm.RedisClient;
import js.npm.Ssh;
import js.npm.Docker;

import ccc.compute.ComputeTools;
import ccc.compute.InstancePool;
import ccc.compute.ComputeQueue;
import ccc.compute.LogStreams;
import ccc.compute.execution.BatchComputeDocker;
import ccc.compute.server.ServerCommands;
import ccc.storage.ServiceStorage;
import ccc.storage.StorageDefinition;
import ccc.storage.StorageSourceType;
import ccc.storage.StorageTools;

import promhx.Promise;
import promhx.Stream;
import promhx.StreamPromises;
import promhx.deferred.DeferredPromise;
import promhx.deferred.DeferredStream;
import promhx.RedisPromises;

import util.streams.StreamTools;
import util.SshTools;

using StringTools;
using util.RedisTools;
using ccc.compute.JobTools;
using ccc.compute.workers.WorkerTools;
using promhx.PromiseTools;
using Lambda;
using util.MapTools;

enum JobEvent
{
	Initializing;
	RegisteringWithDatabase;
	CreatingDockerContainer;
	StartedDockerContainer;
	FinishedDockerContainer;
}

@:enum
abstract JobExecutionState(String) {
  var WaitingForExecution = "waiting";
  var Executing = "executing";
  var Aborted = "aborted";
  var Finished = "finished";
  var ResumingFromRestart = "resuming_from_restart";
}

class Job
{
	public static function writeJobResults(job :QueueJobDefinitionDocker, fs :ServiceStorage, batchJobResult :BatchJobResult, finishedStatus :JobFinishedStatus) :Promise<JobResult>
	{
		var jobStorage = fs.clone();
		/* The e.g. S3 URL. Otherwise empty */
		var externalBaseUrl = fs.getExternalUrl();

		var jobResult :JobResult = {
			id: job.id,
			status: finishedStatus,
			exitCode: batchJobResult.exitCode,
			stdout: externalBaseUrl + job.item.resultDir() + STDOUT_FILE,
			stderr: externalBaseUrl + job.item.resultDir() + STDERR_FILE,
			resultJson: externalBaseUrl + job.item.resultJsonPath(),
			inputsBaseUrl: externalBaseUrl + job.item.inputDir(),
			outputsBaseUrl: externalBaseUrl + job.item.outputDir(),
			inputs: job.item.inputs,
			outputs: batchJobResult.outputFiles,
			error: batchJobResult.error,
		};
		Log.debug({jobid:job.id, exitCode:batchJobResult.exitCode});
		jobStorage = jobStorage.appendToRootPath(job.item.resultDir());
		return Promise.promise(true)
			.pipe(function(_) {
				if (batchJobResult.copiedLogs) {
					return jobStorage.exists(STDOUT_FILE)
						.pipe(function(exists) {
							if (!exists) {
								jobResult.stdout = null;
							}
							return jobStorage.exists(STDERR_FILE);
						})
						.then(function(exists) {
							if (!exists) {
								jobResult.stderr = null;
							}
							return true;
						});
				} else {
					jobResult.stdout = null;
					jobResult.stderr = null;
					return Promise.promise(true);
				}
			})
			.pipe(function(_) {
				return jobStorage.writeFile(RESULTS_JSON_FILE, StreamTools.stringToStream(Json.stringify(jobResult)));
			})
			.pipe(function(_) {
				if (externalBaseUrl != '') {
					return promhx.RetryPromise.pollRegular(function() {
						return jobStorage.readFile(RESULTS_JSON_FILE)
							.pipe(function(readable) {
								return StreamPromises.streamToString(readable);
							})
							.then(function(s) {
								return null;
							});
						}, 10, 50, '${RESULTS_JSON_FILE} check', false)
						.then(function(resultsjson) {
							return null;
						});
				} else {
					return Promise.promise(null);
				}
			})
			.then(function(_) {
				return jobResult;
			});
	}

	public static function logStdStreamsToElasticSearch(redis :RedisClient, fs :ServiceStorage, jobId :JobId) :Promise<Bool>
	{
		// FluentTools
		Assert.notNull(redis);
		Assert.notNull(fs);
		Assert.notNull(jobId);
		return ServerCommands.getStdout(redis, fs, jobId)
			.pipe(function(stdout) {
				if (stdout != null) {
					FluentTools.logToFluent({source:STDOUT_FILE, jobId:jobId, stdout:stdout});
				}
				return Promise.promise(true);
			})
			.pipe(function(_) {
				return ServerCommands.getStderr(redis, fs, jobId);
			})
			.pipe(function(stderr) {
				if (stderr != null) {
					FluentTools.logToFluent({source:STDERR_FILE, jobId:jobId, stdout:stderr});
				}
				return Promise.promise(true);
			});
	}

	public var id (get, null) :ComputeJobId;
	public var computeJobId (get, null) :ComputeJobId;
	public var jobId (get, null) :JobId;
	public var logToConsole :Bool = false;
	var _computeId :ComputeJobId;
	var _job :QueueJobDefinitionDocker;
	var _streams :LogStreams;
	var _statusStream :Stream<JobStatusUpdate>;
	var _currentInternalState :JobStatusUpdate;
	var _disposed :Bool = false;
	var _cancelWorkingJob :Void->Void;
	var _removedFromDockerHost :Bool = false;
	var log :AbstractLogger;

	@inject public var _redis :RedisClient;
	@inject public var _fs :ServiceStorage;
	public var _workerStorage :ServiceStorage;

	static var ALL_JOBS = new Map<ComputeJobId, Job>();

	public function new(computeId :ComputeJobId)
	{
		log = Logger.child({'component':'job', 'computejobid':computeId});
		Assert.that(!ALL_JOBS.exists(computeId));
		_computeId = computeId;
		ALL_JOBS.set(computeId, this);
	}

	@post
	public function postInject()
	{
		init();
	}

	public function kill() :Promise<Bool>
	{
		return finishJob(JobFinishedStatus.Killed)
			.thenTrue();
	}

	public function init()
	{
		//Get the job info
		Assert.notNull(_redis, 'Job does not have redis client injected');
		var redis = _redis;
		var computeJobId = _computeId;

		return Promise.promise(true)
			.pipe(function(_) {
				if (_disposed) {
					return Promise.promise(null);
				} else {
					return ComputeQueue.getJobDescriptionFromComputeId(redis, computeJobId);
				}
			})
			.then(function(job :QueueJobDefinitionDocker) {
				if (!_disposed) {
					_job = job;
					log = log.child({jobid:job.id});
					if (_job.item.inputs != null) {
						if (!Std.is(_job.item.inputs, Array)) {
							_job.item.inputs = [];
						}
					}

					//TODO: This is a weak point, one redis client per job. There should be one
					//stream for the entire process, not one per job. This will break because
					//redis has a maximum# of client connections.
					//Fix this asap.
					_statusStream = RedisTools.createJsonStreamFromHash(_redis, ComputeQueue.REDIS_CHANNEL_STATUS, ComputeQueue.REDIS_KEY_STATUS, _job.id);
					_statusStream
						.then(onStatus);
				}
				return true;
			});
	}

	function executeJob() :ExecuteJobResult
	{
		var workerStorage = if (_workerStorage != null) {
			_workerStorage;
		} else {
			var workerStorageConfig :StorageDefinition = {
				type: StorageSourceType.Sftp,
				rootPath: WORKER_JOB_DATA_DIRECTORY_WITHIN_CONTAINER,
				sshConfig: _job.worker.ssh
			};
			StorageTools.getStorage(workerStorageConfig);
		}
		return BatchComputeDocker.executeJob(_redis, _job, _fs, workerStorage, log);
	}

	function onStatus(update :JobStatusUpdate)
	{
		if (_disposed) {
			return;
		}
		if (update == null) {
			return;
		}
		if (_currentInternalState != null && _currentInternalState.computeJobId != computeJobId) {
			log.warn({log:'Job=$jobId Job.computeJobId mismatch, ignoring status update ${_currentInternalState.JobStatus}'});
			return;
		}
		if (_currentInternalState != null && _currentInternalState.JobStatus == update.JobStatus) {
			return;
		}
		_currentInternalState = update;

		log.info({'message':'job_status_update', JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus, computejobid:computeJobId});

		switch(_currentInternalState.JobStatus) {
			case Pending://We don't do anything, and we probably don't exist
				Promise.promise(true);
			case Working:
				// Eventually we'll restart, for now, just run the damn job
				var p = Promise.promise(true)
					.pipe(function(_) {
						var executecallResult = executeJob();
						executecallResult.promise.catchError(function(err) {
							_cancelWorkingJob = null;
							var batchJobResult = {exitCode:-1, error:err, copiedLogs:false};
							log.error({exitCode:-1, error:err, JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
							if (!_disposed && _currentInternalState.JobStatus == JobStatus.Working) {
								writeJobResults(_job, _fs, batchJobResult, JobFinishedStatus.Failed)
									.then(function(_) {
										return finishJob(JobFinishedStatus.Failed, Std.string(err));
									});
							}
						});
						//This can be called in case the job is killed
						_cancelWorkingJob = executecallResult.cancel;
						return executecallResult.promise
							.pipe(function(batchJobResult) {
								_cancelWorkingJob = null;
								if (!_disposed && _currentInternalState.JobStatus == JobStatus.Working) {
									var finishedStatus = batchJobResult.error != null ? JobFinishedStatus.Failed : JobFinishedStatus.Success;
									return writeJobResults(_job, _fs, batchJobResult, finishedStatus)
										.pipe(function(_) {
											return finishJob(finishedStatus, batchJobResult.error)
												.thenTrue();
										});
								} else {
									return Promise.promise(true);
								}
							});
							// .then(function(_) {
							// 	try {
							// 		if (_redis != null) {
							// 			logStdStreamsToElasticSearch(_redis, _fs, _job.id);
							// 		}
							// 	} catch (err :Dynamic) {
							// 		Log.error({error:err});
							// 	}
							// 	return true;
							// });
					});
				p.catchError(function(err) {
					// This is no longer needed
					_cancelWorkingJob = null;
					var batchJobResult = {exitCode:-1, copiedLogs:false, error:err};
					log.error({exitCode:-1, error:err, state:_currentInternalState});
					if (!_disposed && _currentInternalState.JobStatus == JobStatus.Working) {
						var finishedStatus = batchJobResult.error != null ? JobFinishedStatus.Failed : JobFinishedStatus.Success;
						writeJobResults(_job, _fs, batchJobResult, finishedStatus)
							.then(function(_) {
								finishJob(finishedStatus, Std.string(err));
							});
					}
				});
				p;
			case Finalizing:
				//Cleanup?
				Assert.notNull(_currentInternalState.JobFinishedStatus);
				var promise = switch(_currentInternalState.JobFinishedStatus) {
					case Success,Failed:
						Promise.promise(true);
					case TimeOut,Killed:
						if (_cancelWorkingJob != null) {
							_cancelWorkingJob();
							_cancelWorkingJob = null;
						}
						//Making copiedLogs:true because check if they're there
						var batchJobResult = {exitCode:-1, copiedLogs:true, error:_currentInternalState.JobFinishedStatus};
						writeJobResults(_job, _fs, batchJobResult, _currentInternalState.JobFinishedStatus)
							.thenTrue();
					case None:
						log.error({log:'case Finalizing JobFinishedStatus==None not handled', JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
						Promise.promise(true);
					default:
						log.error({log:'case Finalizing JobFinishedStatus not handled/unrecognized', JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
						Promise.promise(true);
				}

				promise
					.pipe(function(_) {
						return removeJobFromDockerHost()
							.errorPipe(function(err) {
								log.error({log:'removeJobFromDockerHost', error:err, JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
								return Promise.promise(true);
							});
					})
					.pipe(function(_) {
						//Remove the job from the worker model
						if (!_disposed) {
							return ComputeQueue.jobFinalized(_redis, computeJobId)
								.errorPipe(function(err) {
									log.error({log:'ComputeQueue.jobFinalized', error:err, JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
									return Promise.promise(true);
								});
						} else {
							return Promise.promise(true);
						};
					});
			case Finished:
				if (!_disposed) {
					InstancePool.removeJob(_redis, computeJobId)
						.errorPipe(function(err) {
							log.error({log:'InstancePool.removeJob', error:err, JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
							return Promise.promise(true);
						})
						.pipe(function(_) {
							if (_redis != null) {
								return ComputeQueue.processPending(_redis)
									.thenTrue();
							} else {
								return Promise.promise(true);
							}
						})
						.pipe(function(_) {
							return dispose()
								.thenTrue();
						});
				} else {
					Promise.promise(true);
				}
			default:
				log.error({log:'unrecognized status _currentInternalState=${_currentInternalState}', JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
				Promise.promise(true);
		}
	}

	public function removeJobFromDockerHost() :Promise<Bool>
	{
		if (_removedFromDockerHost) {
			return Promise.promise(true);
		} else {
			_removedFromDockerHost = true;
			var docker = _job.worker.getInstance().docker();
			var suppressErrorIfContainerNotFound = true;
			return DockerJobTools.removeContainer(docker, id, suppressErrorIfContainerNotFound)
				.then(function(_) {
					log.debug({log:'Removed container from docker'});
					return true;
				})
				.errorPipe(function(err) {
					Log.error({log:'Failed to remove container from docker, perhaps it was never created', error:err});
					return Promise.promise(false);
				});
		}
	}

	public function dispose() :Promise<Bool>
	{
		ALL_JOBS.remove(_computeId);
		if (_disposed) {
			return Promise.promise(true);
		} else {
			_disposed = true;
			if (_cancelWorkingJob != null) {
				_cancelWorkingJob();
				_cancelWorkingJob = null;
			}
			if (_statusStream != null) {
				_statusStream.end();
				_statusStream = null;
			}
			return removeJobFromDockerHost()
				.pipe(function(_) {
					var streams = _streams;
					_streams = null;
					return streams != null ? streams.dispose() : Promise.promise(true);
				})
				.errorPipe(function(err) {
					log.error({log:'Failed to removeJobFromDockerHost', error:err});
					return Promise.promise(true);
				})
				.then(function(_) {
					_redis = null;
					return true;
				});
		}
	}

	public function toString() :String
	{
		return '[Job id=$_computeId _currentInternalState=$_currentInternalState _disposed=$_disposed _job=$_job]';
	}

	function finishJob(finishedStatus :JobFinishedStatus, ?error :Dynamic) :Promise<QueueJobDefinitionDocker>
	{
		if (_redis != null) {
			return ComputeQueue.finishComputeJob(_redis, computeJobId, finishedStatus, error);
		} else {
			return Promise.promise(null);
		}
	}

	function getContainer() :Promise<DockerContainer>
	{
		return DockerJobTools.getContainerFromJob(_job);
	}

	inline function get_id() :ComputeJobId
	{
		return _computeId;
	}

	inline function get_computeJobId() :ComputeJobId
	{
		return _computeId;
	}

	inline function get_jobId() :JobId
	{
		return _job.id;
	}
}