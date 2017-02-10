package ccc.compute.server.execution;

/**
 * Represents a running job in a docker container.
 * Actively monitors the job.
 * TODO: Also can resume
 */

import util.DockerTools;

import ccc.compute.server.FluentTools;
import ccc.compute.server.execution.BatchComputeDocker;

import js.npm.RedisClient;
import js.npm.ssh2.Ssh;

import ccc.storage.*;

import util.streams.StreamTools;
import util.SshTools;

using util.RedisTools;
using ccc.compute.server.JobTools;
using ccc.compute.server.workers.WorkerTools;
using util.MapTools;

class Job
{
	public static function writeJobResults(redis :RedisClient, job :QueueJobDefinitionDocker, fs :ServiceStorage, batchJobResult :BatchJobResult, finishedStatus :JobFinishedStatus) :Promise<{write:Void->Promise<JobResult>, jobResult:JobResult}>
	{
		var run = function() {
			var jobStorage = fs.clone();
			/* The e.g. S3 URL. Otherwise empty */
			var externalBaseUrl = fs.getExternalUrl();

			var jobStats :JobStats = redis;

			var appendStdOut = job.item.appendStdOut == true;
			var appendStdErr = job.item.appendStdErr == true;

			Log.debug({jobid:job.id, exitCode:batchJobResult.exitCode});
			var jobResultsStorage = jobStorage.appendToRootPath(job.item.resultDir());
			var jobResult :JobResult = null;

			return Promise.promise(true)
				.pipe(function(_) {
					return jobStats.getPretty(job.id);
				})
				.then(function(prettyJobStats) {
					jobResult = {
						jobId: job.id,
						status: finishedStatus,
						exitCode: batchJobResult.exitCode,
						stdout: fs.getExternalUrl(job.item.stdoutPath()),
						stderr: fs.getExternalUrl(job.item.stderrPath()),
						resultJson: externalBaseUrl + job.item.resultJsonPath(),
						inputsBaseUrl: externalBaseUrl + job.item.inputDir(),
						outputsBaseUrl: externalBaseUrl + job.item.outputDir(),
						inputs: job.item.inputs,
						outputs: batchJobResult.outputFiles,
						error: batchJobResult.error,
						definition: job.item,
						stats: prettyJobStats
					};
					Log.trace(Json.stringify(jobResult, null, '  '));
					return jobResult;
				})
				.pipe(function(jobResult) {
					if (batchJobResult.copiedLogs) {

						return jobResultsStorage.exists(STDOUT_FILE)
							.pipe(function(exists) {
								if (!exists) {
									jobResult.stdout = null;
									return Promise.promise(true);
								} else {
									if (appendStdOut) {
										return jobResultsStorage.readFile(STDOUT_FILE)
											.pipe(function(stream) {
												return StreamPromises.streamToString(stream)
													.then(function(stdoutString) {
														if (stdoutString != null) {
															Reflect.setField(jobResult, 'stdout', stdoutString.split('\n'));
														} else {
															Reflect.setField(jobResult, 'stdout', null);
														}
														return true;
													})
													.errorPipe(function(err) {
														Log.error(Json.stringify(err));
														return Promise.promise(true);
													});
											});
									} else {
										return Promise.promise(true);
									}
								}

								return jobResultsStorage.exists(STDERR_FILE);
							})
							.pipe(function(exists) {
								if (!exists) {
									jobResult.stderr = null;
									return Promise.promise(true);
								} else {
									if (appendStdErr) {
										return jobResultsStorage.readFile(STDERR_FILE)
											.pipe(function(stream) {
												return StreamPromises.streamToString(stream)
													.then(function(stderrString) {
														if (stderrString != null) {
															Reflect.setField(jobResult, 'stderr', stderrString.split('\n'));
														} else {
															Reflect.setField(jobResult, 'stderr', null);
														}
														return true;
													})
													.errorPipe(function(err) {
														Log.error(Json.stringify(err));
														return Promise.promise(true);
													});
											});
									} else {
										return Promise.promise(true);
									}
								}
							});
					} else {
						jobResult.stdout = null;
						jobResult.stderr = null;
						return Promise.promise(true);
					}
				})
				.pipe(function(_) {
					return jobResultsStorage.writeFile(RESULTS_JSON_FILE, StreamTools.stringToStream(Json.stringify(jobResult)));
				})
				.pipe(function(_) {
					if (externalBaseUrl != '') {
						return promhx.RetryPromise.pollRegular(function() {
							return jobResultsStorage.readFile(RESULTS_JSON_FILE)
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
		return run()
			.then(function(jobResult) {
				return {write:run, jobResult:jobResult};
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
			.errorPipe(function(err) {
				log.error({error:err, message:'Failed to initialized job, removing'});
				if (_redis != null) {
					return ComputeQueue.jobFinalized(_redis, computeJobId)
						.errorPipe(function(err) {
							log.error({log:'ComputeQueue.jobFinalized after failing to load', error:err});
							return Promise.promise(true);
						})
						.pipe(function(_) {
							return dispose()
								.thenVal(null);
						});
				} else {
					return dispose()
						.thenVal(null);
				}
			})
			.then(function(job :QueueJobDefinitionDocker) {
				if (!_disposed && job != null) {
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
				credentials: _job.worker.ssh
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

							log.error(try {Json.stringify(err);} catch(_:Dynamic) {err;});
							_cancelWorkingJob = null;

							function writeFailure() {
								//Write job as a failure
								//This should actually never happen, or the failure
								//should be handled
								var batchJobResult = {exitCode:-1, error:err, copiedLogs:false};
								log.error({exitCode:-1, error:err, JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
								if (!_disposed && _currentInternalState.JobStatus == JobStatus.Working) {
									writeJobResults(_redis, _job, _fs, batchJobResult, JobFinishedStatus.Failed)
										.then(function(result) {
											return finishJob(JobFinishedStatus.Failed, Std.string(err))
												.pipe(function(_) {
													return result.write();
												});
										});
								}
							}

							//Check if we can reach the worker. If not, then the
							//worker died at an inconvenient time, so we requeue
							//this job
							checkMachine()
								.then(function(ok) {
									if (_redis != null) {
										if (ok) {
											writeFailure();
										} else {
											log.warn('Job failed but worker failed check, so requeuing job');
											ComputeQueue.requeueJob(_redis, _job.computeJobId);
											dispose();
										}
									}
								});
						});
						//This can be called in case the job is killed
						_cancelWorkingJob = executecallResult.cancel;
						return executecallResult.promise
							.pipe(function(batchJobResult) {
								_cancelWorkingJob = null;
								if (!_disposed && _currentInternalState.JobStatus == JobStatus.Working) {
									if (batchJobResult.exitCode == 137) {
										log.warn('Job failed (exitCode == 137) which means there was a docker issue, requeuing');
										return ComputeQueue.getJobStats(_redis, jobId)
											.pipe(function(stats) {
												if (stats.dequeueCount >= 3) {//Hard coded max retries
													var finishedStatus = JobFinishedStatus.Failed;
													return writeJobResults(_redis, _job, _fs, batchJobResult, finishedStatus)
														.pipe(function(resultBlob) {
															return finishJob(finishedStatus, 'Job failed (exitCode == 137) which means there was a docker issue')
																.pipe(function(_) {
																	return resultBlob.write();
																})
																.thenTrue();
														});
												} else {
													log.warn({message:'Requeuing', dequeueCount:stats.dequeueCount, batchJobResult:batchJobResult});
													ComputeQueue.requeueJob(_redis, _job.computeJobId);
													dispose();
													return Promise.promise(true);
												}
											});
									} else {
										var finishedStatus = batchJobResult.error != null ? JobFinishedStatus.Failed : JobFinishedStatus.Success;
										return writeJobResults(_redis, _job, _fs, batchJobResult, finishedStatus)
											.pipe(function(resultBlob) {
												return finishJob(finishedStatus, batchJobResult.error)
													.pipe(function(_) {
														return resultBlob.write();
													})
													.thenTrue();
											});
									}
								} else {
									return Promise.promise(true);
								}
							});
					});
				p.catchError(function(err) {
					// This is no longer needed
					_cancelWorkingJob = null;
					var batchJobResult = {exitCode:-1, copiedLogs:false, error:err};
					log.error({exitCode:-1, error:err, state:_currentInternalState});
					if (!_disposed && _currentInternalState.JobStatus == JobStatus.Working) {
						var finishedStatus = batchJobResult.error != null ? JobFinishedStatus.Failed : JobFinishedStatus.Success;
						writeJobResults(_redis, _job, _fs, batchJobResult, finishedStatus)
							.then(function(resultBlob) {
								finishJob(finishedStatus, Std.string(err))
									.pipe(function(_) {
										return resultBlob.write();
									});
							})
							.catchError(function(err) {
								log.error({error:err, state:_currentInternalState, message:'Failed to write job results'});
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
						writeJobResults(_redis, _job, _fs, batchJobResult, _currentInternalState.JobFinishedStatus)
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
					})
					.catchError(function(err) {
						log.error({log:'ComputeQueue.jobFinalized', error:err, JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
					});
			case Finished:
				if (!_disposed) {
					InstancePool.removeJob(_redis, computeJobId)
						.errorPipe(function(err) {
							log.error({log:'InstancePool.removeJob', error:err, JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
							return Promise.promise(true);
						})
						.pipe(function(_) {
							//We may already be shut down
							if (_redis != null) {
								return ComputeQueue.processPending(_redis)
									.thenTrue();
							} else {
								return Promise.promise(true);
							}
						})
						.errorPipe(function(err) {
							log.error({error:err, JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
							return Promise.promise(true);
						})
						.pipe(function(_) {
							return dispose()
								.errorPipe(function(err) {
									log.error({error:err, JobStatus:_currentInternalState.JobStatus, JobFinishedStatus:_currentInternalState.JobFinishedStatus});
									return Promise.promise(true);
								})
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
		/**
		 * This is now handled from BatchComputeDocker due to the
		 * need to remove the container before removing the volumes
		 * but I'm keep this here just in case I need to refactor
		 * and forget to remove containers from the docker host
		 */
		_removedFromDockerHost = true;
		return Promise.promise(true);
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
					log.warn({log:'Failed to removeJobFromDockerHost', error:err});
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
			var jobStats :JobStats = _redis;
			jobStats.jobCopiedLogs(jobId);
			jobStats.jobFinished(jobId);
			return ComputeQueue.finishComputeJob(_redis, computeJobId, finishedStatus, error);
		} else {
			return Promise.promise(null);
		}
	}

	function checkMachine() :Promise<Bool>
	{
		return cloud.MachineMonitor.checkMachine(_job.worker.docker, _job.worker.ssh);
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