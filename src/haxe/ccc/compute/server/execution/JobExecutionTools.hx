package ccc.compute.server.execution;

/**
 * Represents a running job in a docker container.
 * Actively monitors the job.
 * TODO: Also can resume
 */

import util.DockerTools;

import ccc.compute.server.logs.FluentTools;
import ccc.compute.server.execution.BatchComputeDocker;

import js.npm.RedisClient;
import js.npm.ssh2.Ssh;

import ccc.storage.*;

import util.streams.StreamTools;
import util.SshTools;

using util.RedisTools;
using util.MapTools;

class JobExecutionTools
{
	public static function writeJobResults(redis :RedisClient, job :DockerBatchComputeJob, fs :ServiceStorage, batchJobResult :BatchJobResult, finishedStatus :JobFinishedStatus) :Promise<{write:Void->Promise<JobResult>, jobResult:JobResult}>
	{
		var run = function() {
			var jobStorage = fs.clone();
			/* The e.g. S3 URL. Otherwise empty */
			var externalBaseUrl = fs.getExternalUrl();

			var jobStats :JobStats = redis;
			var jobId = job.jobId;

			var appendStdOut = job.appendStdOut == true;
			var appendStdErr = job.appendStdErr == true;

			Log.debug({jobid:jobId, exitCode:batchJobResult.exitCode});
			var jobResultsStorage = jobStorage.appendToRootPath(job.resultDir());
			var jobResult :JobResult = null;

			var typeofError = untyped __typeof__(batchJobResult.error);
			return Promise.promise(true)
				.pipe(function(_) {
					return jobStats.jobFinished(jobId);
				})
				.pipe(function(_) {
					return jobStats.getPretty(jobId);
				})
				.then(function(prettyJobStats) {
					jobResult = {
						jobId: jobId,
						status: finishedStatus,
						exitCode: batchJobResult.exitCode,
						stdout: fs.getExternalUrl(job.stdoutPath()),
						stderr: fs.getExternalUrl(job.stderrPath()),
						resultJson: externalBaseUrl + job.resultJsonPath(),
						inputsBaseUrl: externalBaseUrl + job.inputDir(),
						outputsBaseUrl: externalBaseUrl + job.outputDir(),
						inputs: job.inputs,
						outputs: batchJobResult.outputFiles,
						error: batchJobResult.error,
						definition: job,
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
					if (jobResult.error != null && untyped __typeof__(jobResult.error) == 'string') {
						try {
							jobResult.error = Json.parse(jobResult.error);
						} catch(e:Dynamic){}
					}
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

	public static function checkMachine(worker :WorkerDefinition) :Promise<Bool>
	{
		return cloud.MachineMonitor.checkMachine(worker.docker, worker.ssh);
	}

	// public static function catchExecuteErrorHandler(job :QueueJobDefinitionDocker, fs :ServiceStorage, log :AbstractLogger) :Dynamic->Void;
	// {
	// 	return function(err) {
	// 		log.error(try {Json.stringify(err);} catch(_:Dynamic) {err;});

	// 		//Write job as a failure
	// 		//This should actually never happen, or the failure
	// 		//should be handled
	// 		var batchJobResult = {exitCode:-1, error:err, copiedLogs:false};
	// 		log.error({exitCode:-1, error:err, JobStatus:null, JobFinishedStatus:null});
	// 		writeJobResults(job, fs, batchJobResult, JobFinishedStatus.Failed)
	// 			.then(function(_) {
	// 				log.debug({job:job.id, message:"Finished writing job"});
	// 				return finishJob(JobFinishedStatus.Failed, Std.string(err));
	// 			})
	// 			.catchError(function(err) {
	// 				log.error({error:err, message:"Failed to write job results", jobId:job.id});
	// 			});
	// 	}
	// }
}