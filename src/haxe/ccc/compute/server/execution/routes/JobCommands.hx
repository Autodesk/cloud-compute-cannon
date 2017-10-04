package ccc.compute.server.execution.routes;

import ccc.compute.worker.ProcessQueue;

import haxe.Resource;
import haxe.remoting.JsonRpc;

import js.npm.redis.RedisClient;
import js.npm.docker.Docker;
import t9.redis.RedisLuaTools;
import js.node.http.*;

import util.DockerTools;
import util.DockerUrl;
import util.DockerRegistryTools;
import util.DateFormatTools;

/**
 * Server API methods
 */
class JobCommands
{
	public static function getAllJobs(injector :Injector) :Promise<Array<JobId>>
	{
		return Jobs.getAllJobs();
	}

	public static function hardStopAndDeleteAllJobs(injector :Injector) :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				return Jobs.getAllJobs();
			})
			.pipe(function(jobIds) {
				//Remove all jobs
				return Promise.whenAll(jobIds.map(function(jobId) {
					return removeJob(injector, jobId);
				}));
			})
			.thenTrue();
	}

	public static function deleteJobFiles(injector :Injector, jobId :JobId) :Promise<Bool>
	{
		var fs :ServiceStorage = injector.getValue(ServiceStorage);
		return Jobs.isJob(jobId)
			.pipe(function(jobExists) {
				if (jobExists) {
					return getJobDefinition(injector, jobId)
						.pipe(function(jobdef) {
							var promises = [JobTools.inputDir(jobdef), JobTools.outputDir(jobdef), JobTools.resultDir(jobdef)]
								.map(function(path) {
									return fs.deleteDir(path)
										.errorPipe(function(err) {
											Log.error({error:err, jobid:jobId, log:'Failed to remove ${path}'});
											return Promise.promise(true);
										});
								});
							return Promise.whenAll(promises)
								.thenTrue();
						});
				} else {
					var path = '${jobId}/';
					return fs.deleteDir(path)
						.errorPipe(function(err) {
							Log.error({error:err, jobid:jobId, log:'Failed to remove ${path}'});
							return Promise.promise(true);
						});
				}
			});
	}

	public static function killJob(injector :Injector, jobId :JobId) :Promise<Bool>
	{
		return JobStateTools.cancelJob(jobId)
			.pipe(function(_) {
				return deleteJobFiles(injector, jobId);
			})
			.thenTrue();
	}

	/**
	 * Removes job from the system, except it DOESN'T remove
	 * job data from the storage service (e.g. S3)
	 * TODO: do NOT ever remove job stats this way except
	 * via a timelime method.
	 * @param  jobId        :JobId        [description]
	 * @param  processQueue :ProcessQueue [description]
	 * @return              [description]
	 */
	public static function removeJob(injector :Injector, jobId :JobId) :Promise<Bool>
	{
		var processQueue :ProcessQueue = injector.getValue(ProcessQueue);
		return Promise.promise(true)
			.pipe(function(_) {
				return JobStateTools.cancelJob(jobId);
			})
			.pipe(function(_) {
				return processQueue.cancel(jobId);
			})
			.pipe(function(_) {
				return JobStateTools.removeJob(jobId);
			})
			.pipe(function(_) {
				Log.warn('No longer removing job stats tools via removeJob');
				// return JobStatsTools.removeJobStats(jobId);
				return Promise.promise(true);
			})
			.pipe(function(_) {
				return Jobs.removeJob(jobId);
			})
			.thenTrue();
	}

	public static function getJobDefinition(injector :Injector, jobId :JobId, ?externalUrl :Bool = true) :Promise<DockerBatchComputeJob>
	{
		Assert.notNull(jobId);
		var fs :ServiceStorage = injector.getValue(ServiceStorage);
		return Jobs.getJob(jobId)
			.pipe(function(jobdef) {
				if (jobdef == null) {
					return getJobResults(injector, jobId)
						.then(function(jobResults) {
							if (jobResults != null) {
								return jobResults.definition;
							} else {
								return null;
							}
						})
						.errorPipe(function(err) {
							return Promise.promise(null);
						});
				} else {
					return Promise.promise(jobdef);
				}
			})
			.then(function(jobdef) {
				if (jobdef != null) {
					var jobDefCopy = Reflect.copy(jobdef);
					jobDefCopy.inputsPath = externalUrl ? fs.getExternalUrl(JobTools.inputDir(jobdef)) : JobTools.inputDir(jobdef);
					jobDefCopy.outputsPath = externalUrl ? fs.getExternalUrl(JobTools.outputDir(jobdef)) : JobTools.outputDir(jobdef);
					jobDefCopy.resultsPath = externalUrl ? fs.getExternalUrl(JobTools.resultDir(jobdef)) : JobTools.resultDir(jobdef);
					jobdef = jobDefCopy;
				}
				return jobdef;
			});
	}

	public static function getJobPath(injector :Injector, jobId :JobId, pathType :JobPathType) :Promise<String>
	{
		return getJobDefinition(injector, jobId, false)
			.then(function(jobdef) {
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
					var fs :ServiceStorage = injector.getValue(ServiceStorage);
					return fs.getExternalUrl(path);
				}
			});
	}

	/**
	 * Returns job results IF the job is finished, otherwise
	 * null if the job doesn't exist or the results are not
	 * ready. This can thus be used in polling attempts,
	 * even if there are better ways. e.g. listening to the
	 * stream.
	 * @param  injector :Injector     [description]
	 * @param  jobId    :JobId        [description]
	 * @return          [description]
	 */
	public static function getJobResults(injector :Injector, jobId :JobId) :Promise<JobResult>
	{
		return Jobs.getJob(jobId)
			.then(function(jobdef) {
				if (jobdef == null) {
					return JobTools.resultJsonPathFromJobId(jobId);
				} else {
					return JobTools.resultJsonPath(jobdef);
				}
			})
			.pipe(function(resultsJsonPath) {
				var fs :ServiceStorage = injector.getValue(ServiceStorage);
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
			});
	}

	public static function getExitCode(injector :Injector, jobId :JobId) :Promise<Null<Int>>
	{
		return getJobResults(injector, jobId)
			.then(function(jobResults) {
				return jobResults != null ? jobResults.exitCode : null;
			});
	}

	public static function getStatus(injector :Injector, jobId :JobId) :Promise<Null<String>>
	{
		return JobStateTools.getStatus(jobId)
			.then(function(status) {
				return '$status';
			});
	}

	public static function getStatusv1(injector :Injector, jobId :JobId) :Promise<Null<String>>
	{
		return JobStateTools.getStatus(jobId)
			.pipe(function(status) {
				switch(status) {
					case Pending,Finished:
						return Promise.promise('${status}');
					case Working:
						return JobStateTools.getWorkingStatus(jobId)
							.then(function(workingStatus) {
								if (workingStatus == JobWorkingStatus.CopyingInputsAndImage) {
									workingStatus = JobWorkingStatus.CopyingInputs;
								}
								if (workingStatus == JobWorkingStatus.CopyingOutputsAndLogs) {
									workingStatus = JobWorkingStatus.CopyingOutputs;
								}
								if (workingStatus == JobWorkingStatus.None) {
									workingStatus = JobWorkingStatus.CopyingInputs;
								}
								return '${workingStatus}';
							});
				}
			});
	}

	public static function getStdout(injector :Injector, jobId :JobId) :Promise<String>
	{
		return getJobResults(injector, jobId)
			.pipe(function(jobResults) {
				if (jobResults == null) {
					return Promise.promise(null);
				} else {
					var path = jobResults.stdout;
					if (path == null) {
						return Promise.promise(null);
					} else {
						return getPathAsString(injector, path);
					}
				}
			});
	}

	public static function getStderr(injector :Injector, jobId :JobId) :Promise<String>
	{
		return getJobResults(injector, jobId)
			.pipe(function(jobResults) {
				if (jobResults == null) {
					return Promise.promise(null);
				} else {
					var path = jobResults.stderr;
					if (path == null) {
						return Promise.promise(null);
					} else {
						return getPathAsString(injector, path);
					}
				}
			});
	}

	public static function returnJobResult(injector :Injector, res :ServerResponse, jobId :JobId, jsonRpcId :Dynamic, wait :Bool, maxDuration :Float)
	{
		if (wait == true) {
			getJobResult(injector, jobId)
				.then(function(jobResult) {
					var jsonRpcRsponse = {
						result: jobResult,
						jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2,
						id: jsonRpcId
					}

					if (jobResult != null && jobResult.error != null) {
						var errorMessage :JobSubmissionError = jobResult.error.message;
						switch(errorMessage) {
							//This is a known client submission error
							case Docker_Image_Unknown:
								res.writeHead(400, {'content-type': 'application/json'});
							//Assume the other errors are internal server errors
							default:
								res.writeHead(500, {'content-type': 'application/json'});
						}
					} else {
						res.writeHead(200, {'content-type': 'application/json'});
					}
					res.end(Json.stringify(jsonRpcRsponse));
				})
				.catchError(function(err) {
					res.writeHead(500, {'content-type': 'application/json'});
					res.end(Json.stringify(err));
				});
		} else {
			res.writeHead(200, {'content-type': 'application/json'});
			var jsonRpcRsponse = {
				result: {jobId:jobId},
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2,
				id: jsonRpcId
			}
			res.end(Json.stringify(jsonRpcRsponse));
		}
	}

	public static function doJobCommand(injector :Injector, jobId :JobId, command :JobCLICommand, ?arg1 :String, ?arg2 :String, ?arg3 :String, ?arg4 :String) :Promise<Dynamic>
	{
		if (jobId == null) {
			return PromiseTools.error('Missing jobId.');
		}
		if (command == null) {
			return PromiseTools.error('Missing command.');
		}

		switch(command) {
			case Remove,RemoveComplete,Kill,Status,Result,ExitCode,Definition,JobStats,Time:
			default:
				return Promise.promise(cast {error:'Unrecognized job subcommand=\'$command\' [remove | kill | result | status | exitcode | stats | definition | time]'});
		}

		var redis :RedisClient = injector.getValue(RedisClient);

		return Promise.promise(true)
			.pipe(function(_) {
				return switch(command) {
					case Remove:
						removeJob(injector, jobId)
							.then(function(r) return cast r);
					case RemoveComplete,Kill:
						killJob(injector, jobId)
							.then(function(r) return cast r);
					case Status:
						getStatus(injector, jobId)
							.then(function(r) return cast r);
					case Result:
						getJobResults(injector, jobId)
							.then(function(r) return cast r);
					case ExitCode:
						getExitCode(injector, jobId)
							.then(function(r) return cast r);
					case JobStats:
						getJobStats(injector, jobId)
							// .then(function(stats) {
							// 	return stats != null ? stats.toJson() : null;
							// })
							.then(function(r) return cast r);
					case Time:
						getJobStats(injector, jobId)
							.then(function(stats) {
								if (stats != null) {
									return stats != null ? stats.toJson() : null;
									var enqueueTime = stats.enqueueTime;
									var finishTime = stats.finishTime;
									var result = {
										start: stats.enqueueTime,
										duration: stats.isFinished() ? stats.finishTime - stats.enqueueTime : null
									}
									return result;
								} else {
									return null;
								}
							})
							.then(function(r) return cast r);
					case Definition:
						getJobDefinition(injector, jobId)
							.then(function(r) return cast r);
				}
			})
			.then(function(result :Dynamic) {
				return cast result;
			});
	}

	public static function getJobResult(injector :Injector, jobId :JobId, ?timeout :Float = 86400000) :Promise<JobResult>
	{
		if (timeout == null) {
			timeout = 86400000;
		}

		var promise = new DeferredPromise();
		var timeoutId = null;
		var stream :Stream<Void> = null;

		function cleanUp() {
			if (timeoutId != null) {
				Node.clearTimeout(timeoutId);
				timeoutId = null;
			}
			if (stream != null) {
				stream.end();
			}
		}

		function resolve(result) {
			cleanUp();
			if (promise != null) {
				promise.resolve(result);
				promise = null;
			}
		}
		function reject(err) {
			cleanUp();
			if (promise != null) {
				promise.boundPromise.reject(err);
				promise = null;
			}
		}

		timeoutId = Node.setTimeout(function() {
			reject({error:'Job Timeout', jobId: jobId, timeout:timeout, httpStatusCode:400});
		}, Std.int(timeout));

		stream = ccc.compute.server.Server.StatusStream
			.then(function(stats :JobStatsData) {
				if (stats != null && jobId == stats.jobId) {
					switch(stats.status) {
						case Pending, Working:
						case Finished:
							getJobResults(injector, jobId)
								.then(function (result) {
									if (result != null) {
										resolve(result);
									}
								});
					}
				}
			});
		stream.catchError(reject);

		getJobResults(injector, jobId)
			.then(function (result) {
				if (result != null) {
					resolve(result);
				}
			});
		return promise.boundPromise;
	}

	/** For debugging */
	public static function getJobStats(injector :Injector, jobId :JobId, ?raw :Bool = false) :Promise<Dynamic>
	{
		if (raw) {
			return cast JobStatsTools.get(jobId);
		} else {
			return JobStatsTools.getPretty(jobId);
		}
	}

	public static function deletingPending(injector :Injector) :Promise<DynamicAccess<String>>
	{
		return pending()
			.pipe(function(jobIds) {
				var result :DynamicAccess<String> = {};
				return Promise.whenAll(jobIds.map(function(jobId) {
					return killJob(injector, jobId)
						.then(function(removeJobResult) {
							result.set(jobId, removeJobResult == true ? 'OK' : 'Did not remove');
							return true;
						})
						.errorPipe(function(err) {
							result.set(jobId, 'Failed to remove jobId=$jobId err=$err');
							return Promise.promise(false);
						});
				}))
				.then(function(_) {
					return result;
				});
			});
	}

	public static function deleteAllJobs(injector :Injector) //:{total:Int,pending:Int,running:Int}
	{
		return deletingPending(injector)
			.pipe(function(pendingDeleted) {
				return killAllWorkingJobs(injector)
					.then(function(workingJobsKilled) {
						return {
							total: pendingDeleted.keys().length + workingJobsKilled.length,
							pending: pendingDeleted.keys().length,
							running: workingJobsKilled.length
						};
					});
			});
	}

	public static function killAllWorkingJobs(injector :Injector) :Promise<Array<JobId>>
	{
		return JobStateTools.getJobsWithStatus(JobStatus.Working)
			.pipe(function(workingJobIds) {
				var promises = workingJobIds.map(function(jobId) {
					return killJob(injector, jobId);
				});
				return Promise.whenAll(promises)
					.then(function(_) {
						return workingJobIds;
					});
			});
	}

	public static function pending() :Promise<Array<JobId>>
	{
		return JobStateTools.getJobsWithStatus(JobStatus.Pending);
	}

	static function getPathAsString(injector :Injector, path :String) :Promise<String>
	{
		var fs :ServiceStorage = injector.getValue(ServiceStorage);
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