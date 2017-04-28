package ccc.compute.server.execution.singleworker;

import ccc.compute.server.execution.JobExecutionTools.*;
import ccc.storage.ServiceStorage;

import js.npm.bull.Bull;

import promhx.deferred.DeferredPromise;

/**
 * The main class for pulling jobs off the queue and
 * executing them.
 *
 * Currently this only supports local job execution
 * meaning this process is expecting to be in the
 * same process as the worker.
 */

typedef RedisConnection = {
	var host :String;
	@:optional var port :Int;
	@:optional var opts :Dynamic;
}

typedef QueueArguments = {
	var redis: RedisConnection;
	var log :AbstractLogger;
}

typedef ProcessArguments = { >QueueArguments,
	@:optional var cpus :Int;
	var remoteStorage :ServiceStorage;
}

typedef QueueJob = {
	var jobId :JobId;
}

enum ProcessFinishReason {
	Cancelled;
	Success(result :JobResult);
	Stalled;
	Error(err :Dynamic);
	Timeout;
	DockerContainerKilled;
}


class ProcessQueue
{
	@inject('REDIS_HOST') public var redisHost :String;
	@inject('REDIS_PORT') public var redisPort :Int;
	@inject public var _redis :RedisClient;
	@inject public var _docker :Docker;
	@inject public var _remoteStorage :ServiceStorage;
	@inject public var _injector :Injector;
	@inject public var _workerController :WorkerController;
	@inject public var log :AbstractLogger;
	@inject('StatusStream') public var statusStream :Stream<JobStatusUpdate>;
	@inject public var internalState :WorkerStateInternal;

	var queueProcess (default, null) :js.npm.bull.Bull.Queue<QueueJob,JobResult>;
	var queueAdd (default, null) :js.npm.bull.Bull.Queue<QueueJob,JobResult>;

	var queueProcessPriority (default, null) :js.npm.bull.Bull.Queue<QueueJob,JobResult>;
	var queueAddPriority (default, null) :js.npm.bull.Bull.Queue<QueueJob,JobResult>;

	public var cpus (get, null):Int;
	var _cpus :Int = 1;
	function get_cpus() :Int {return _cpus;}

	public var jobs (get, null):Int;
	var _jobs :Int = 0;
	function get_jobs() :Int {return _jobs;}

	public var ready (get, null) :Promise<Bool>;
	function get_ready() :Promise<Bool> {return _ready.boundPromise;}
	var _ready :DeferredPromise<Bool> = new DeferredPromise();

	// public var jobIds :Array<JobId> = [];
	public var _localJobProcess :Map<JobId,JobProcessObject> = new Map();
	// public var _localJobProcess :Map<JobId,JobProcessObject> = new Map();

	public function new() {}

	public function isQueueEmpty() :Bool
	{
		return !_localJobProcess.keys().hasNext();
	}

	/**
	 * This adds the job to the queue, it does not add the
	 * job to this instance.
	 * @param job :QueueJobDefinitionDocker [description]
	 */
	public function add(job :QueueJobDefinitionDocker) :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				var jobs :Jobs = _redis;
				var jobStats :JobStats = _redis;
				var jobStateTools :JobStateTools = _redis;
				return Promise.whenAll([
					jobs.setJob(job.id, job.item),
					jobs.setJobParameters(job.id, job.parameters),
					jobStateTools.setStatus(job.id, JobStatus.Pending),
					jobStats.jobEnqueued(job.id)
				]);
			})
			.then(function(_) {
				if (job.priority == true) {
					queueAddPriority.add({jobId:job.id}, {removeOnComplete:true});
				} else {
					queueAdd.add({jobId:job.id}, {removeOnComplete:true});
				}
				return true;
			});
	}

	public function cancel(jobId :JobId) :Promise<Bool>
	{
		var jobProcess = _localJobProcess.get(jobId);
		if (jobProcess != null) {
			jobProcess.cancel();
		}
		return Promise.promise(true);
	}

	public function stopQueue() :Promise<Bool>
	{
		queueProcess.close();
		queueProcessPriority.close();
		if (_jobs == 0) {
			return Promise.promise(true);
		} else {
			var promise = new DeferredPromise();
			queueProcess.on(QueueEvent.Completed, function(job, result) {
				if (_jobs == 0 && !promise.isResolved()) {
					promise.resolve(true);
				} else {
					log.warn('stopQueue but _jobs=$_jobs and just got event=${QueueEvent.Completed}. When will this end?');
					Node.setTimeout(function() {
						if (!promise.isResolved()) {
							if (_jobs == 0) {
								promise.resolve(true);
							}
						}
					}, 5000);
				}
			});
			return promise.boundPromise;
		}
	}

	function jobProcesser(queueJob :Job<QueueJob>, done :Done2<JobResult>) :Void
	{
		var Jobs :Jobs = _redis;
		var jobProcessObject = new JobProcessObject(queueJob, done);
		_injector.injectInto(jobProcessObject);

		Assert.notNull(jobProcessObject.jobId);
		_localJobProcess.set(jobProcessObject.jobId, jobProcessObject);

		var jobId = queueJob.data.jobId;

		var internalState :WorkerStateInternal = _injector.getValue('ccc.compute.shared.WorkerStateInternal');
		var workingJobs : Array<JobId> = internalState.jobs;
		if (!workingJobs.has(jobId)) {
			workingJobs.push(jobId);
		}

		Jobs.setJobWorker(jobId, _workerController.id)
			.pipe(function(_) {
				return jobProcessObject.finished;
			})
			.then(function(reason) {
				switch(reason) {
					case Cancelled,Timeout://Do nothing
					case Success(result):
						//The results have already been written, so nothing more to do
					case Stalled:
					case Error(err):
					case DockerContainerKilled:
						var jobStats :JobStats = _redis;
						jobStats.jobEnqueued(jobId)
							.then(function(_) {
								queueAdd.add({jobId:jobId}, {removeOnComplete:true});
								return true;
							}).catchError(function(err) log.error({jobId:jobId,error:err,log:'Failed to requeue job after it was killed'}));
				}
				return reason;
			})
			.errorPipe(function(err) {
				log.error({jobId: jobProcessObject.jobId, error:err, log:'jobProcesser jobProcessObject.finished'});
				return Promise.promise(ProcessFinishReason.Error(err));
			})
			.then(function(_) {
				jobProcessObject.dispose();
				workingJobs.remove(jobId);
				if (_localJobProcess.get(jobProcessObject.jobId) == jobProcessObject) {
					_localJobProcess.remove(jobProcessObject.jobId);
				}
				return true;
			});
	}

	@post
	public function postInject()
	{
		log = log.child({c:ProcessQueue});

		statusStream.then(function(statusUpdate) {
			if (_localJobProcess.exists(statusUpdate.jobId)) {
				traceCyan('statusUpdate=${statusUpdate}');
				if (statusUpdate.statusFinished == JobFinishedStatus.TimeOut) {
					_localJobProcess.get(statusUpdate.jobId).timeout();
				} else if (statusUpdate.statusFinished == JobFinishedStatus.Killed) {
					_localJobProcess.get(statusUpdate.jobId).cancel();
				}
			}
		});

		_cpus = 1;

		DockerPromises.info(_docker)
			.then(function(dockerInfo) {
				_cpus = dockerInfo.NCPU;
				internalState.ncpus = dockerInfo.NCPU;

				var args :ProcessArguments = {
					redis : {
						host: redisHost,
						port: redisPort
					},
					cpus : _cpus,
					remoteStorage: _remoteStorage,
					log: log
				};

				queueProcess = createProcessorQueue(args, jobProcesser);
				queueAdd = createAddingQueue(args);

				queueProcessPriority = createProcessorQueue(args, jobProcesser, true);
				queueAddPriority = createAddingQueue(args, true);

				var queues = [queueProcess, queueProcessPriority];
				var readyEvents = [];

				for (q in queues) {
					q.once(QueueEvent.Ready, function() {
						log.debug({e:QueueEvent.Ready});
						readyEvents.push(true);
						if (readyEvents.length >= queues.length) {
							_ready.resolve(true);
						}
					});

					q.on(QueueEvent.Error, function(err) {
						log.error({e:QueueEvent.Error, error:Json.stringify(err)});
					});

					q.on(QueueEvent.Active, function(job, promise) {
						try {
							log.debug({e:QueueEvent.Active, job:job.data});
						} catch(err :Dynamic) {trace(err);}
					});

					q.on(QueueEvent.Stalled, function(job) {
						log.warn({e:QueueEvent.Stalled, job:job.data});
					});

					q.on(QueueEvent.Progress, function(job, progress) {
						log.debug({e:QueueEvent.Progress, job:job.data, progress:progress});
					});

					q.on(QueueEvent.Completed, function(job, result) {
						log.debug({e:QueueEvent.Completed, job:job.data, result:result});
					});

					q.on(QueueEvent.Failed, function(job, error :js.Error) {
						log.error({e:QueueEvent.Failed, job:job.data, error:error});
						if (error.message != null && error.message.indexOf('job stalled more than allowable limit') > -1) {
							job.retry();
						}
					});

					q.on(QueueEvent.Paused, function() {
						log.info({e:QueueEvent.Paused});
					});

					q.on(QueueEvent.Resumed, function(job) {
						log.info({e:QueueEvent.Resumed, job:job.data});
					});

					q.on(QueueEvent.Cleaned, function(jobs) {
						log.debug({e:QueueEvent.Cleaned, jobs:jobs.map(function(j) return j.data).array()});
						return null;
					});
				}
			});
	}

	static function createProcessorQueue(args :ProcessArguments, jobProcessor: Job<QueueJob>->Done2<JobResult>->Void, ?priority :Bool = false)
	{
		var redisHost :String = args.redis.host;
		var redisPort :Int = args.redis.port != null ? args.redis.port : DEFAULT_REDIS_PORT;
		var cpus :Int = args.cpus != null ? args.cpus : 1;
		var queueName :String = priority ? BullQueueNames.JobQueuePriority : BullQueueNames.JobQueue;
		var queue = new Queue(queueName, redisPort, redisHost);
		function processor(job, done) {
			jobProcessor(job, done);
		}
		queue.process(cpus, processor);
		return queue;
	}

	static function createAddingQueue(args :ProcessArguments, ?priority :Bool = false)
	{
		var redisHost :String = args.redis.host;
		var redisPort :Int = args.redis.port != null ? args.redis.port : DEFAULT_REDIS_PORT;
		var queueName :String = priority ? BullQueueNames.JobQueuePriority : BullQueueNames.JobQueue;
		var queue = new Queue(queueName, redisPort, redisHost);
		return queue;
	}
}

class JobProcessObject
{
	/**
	 * If an error is thrown
	 */
	public var finished (default, null):Promise<ProcessFinishReason>;

	@inject public var _redis :RedisClient;
	@inject public var _remoteStorage :ServiceStorage;
	@inject public var _workerController :WorkerController;
	@inject public var log :AbstractLogger;
	@inject public var _workerState :WorkerStateInternal;

	public var jobId (default, null) :JobId;
	var _cancelled :Bool = false;
	// var _requeued :Bool = false;

	var _queueJob :Job<QueueJob>;
	var _done :Done2<JobResult>;
	var _isFinished :Bool = false;

	var _deferred :DeferredPromise<ProcessFinishReason>;
	var _killedDeferred :DeferredPromise<Bool> = new DeferredPromise();

	public function new(queueJob :Job<QueueJob>, done :Done2<JobResult>)
	{
		_queueJob = queueJob;
		_done = done;
		var jobData = queueJob.data;
		this.jobId = jobData.jobId;
		_deferred = new DeferredPromise();
		this.finished = _deferred.boundPromise;
	}

	/**
	 * This can be called when it becomes stalled.
	 * This ensures that no more actions will be taken.
	 * @return [description]
	 */
	public function dispose()
	{
		_isFinished = true;
	}

	@post
	public function postInject()
	{
		log = log.child({jobId:jobId});
		Assert.notNull(_workerState.id);
		jobProcesser();
	}

	/**
	 * Called externally, by the user or system
	 * @return [description]
	 */
	public function cancel()
	{
		_cancelled = true;
		finish(ProcessFinishReason.Cancelled);
	}

	public function timeout()
	{
		traceCyan('Calling timeout on process queue job');
		_cancelled = true;
		finish(ProcessFinishReason.Timeout);
	}

	// public function requeue()
	// {
	// 	_requeued = true;
	// }

	public function finish(reason :ProcessFinishReason) :Void
	{
		if (_isFinished) {
			log.warn('Job finish call, but job already finished');
			return;
		}
		_isFinished = true;
		log.info({log:'removing from queue', reason:reason.getName()});
		var Jobs :Jobs = _redis;
		Jobs.removeJobWorker(jobId, _workerState.id)
			.then(function(_) {
				switch(reason) {
					case Cancelled:
						_cancelled = true;
						_done(null, null);
						_deferred.resolve(reason);
						_killedDeferred.resolve(true);
					case Success(jobResult):
						_done(null, jobResult);
						_deferred.resolve(reason);
					case Stalled:
						log.warn({jobId: jobId, log:'Got stalled job, hopefully it is back on the queue'});
						_killedDeferred.resolve(true);
						_deferred.resolve(reason);
					case Error(err):
						if (err.message != null && err.message == JobSubmissionError.Docker_Image_Unknown) {
							_done(null, null);
							_deferred.resolve(reason);
						} else {
							log.warn({jobId: jobId, error:err, log:'Got error, retrying job'});
							var jobStateTools :JobStateTools = _redis;
							jobStateTools.setStatus(jobId, JobStatus.Pending)
								.then(function(_) {
									// _done(err, null);
									_deferred.resolve(reason);
									_queueJob.retry();
								});
						}
					case Timeout:
						_done(null, null);
						_deferred.resolve(reason);
						_killedDeferred.resolve(true);
					case DockerContainerKilled:
						var jobStateTools :JobStateTools = _redis;
						jobStateTools.setStatus(jobId, JobStatus.Pending)
							.then(function(_) {
								_done(null, null);
								_deferred.resolve(reason);
								// _queueJob.retry();
							});
				}
			});
	}

	function jobProcesser() :Void
	{
		var queueJob = _queueJob;
		var done = _done;
		try {
			var jobs :Jobs = _redis;
			var jobStateTools :JobStateTools = _redis;

			var error :Dynamic = null;


			jobStateTools.setStatus(jobId, JobStatus.Working)
				.pipe(function(_) {
					return jobs.getJob(jobId);
				})
				.pipe(function(job) {
					var executeBlob = null;
					try {
						executeBlob = BatchComputeDocker.executeJob(_redis, job, DOCKER_CONNECT_OPTS_LOCAL, _remoteStorage, _killedDeferred.boundPromise, log);
					} catch(err :Dynamic) {
						log.error({error:err});
						finish(ProcessFinishReason.Error(err));
						return Promise.promise(true);
					}

					return executeBlob.promise
						.pipe(function(batchJobResult :BatchJobResult) {
							traceCyan('batchJobResult=${batchJobResult}');
							if (_isFinished) {
								return Promise.promise(true);
							} else {
								//This means that the container was killed externally
								if (batchJobResult.exitCode == 137) {
									finish(ProcessFinishReason.DockerContainerKilled);
									return Promise.promise(true);
								} else if (batchJobResult.timeout) {
									return writeJobResults(_redis, job, _remoteStorage, batchJobResult, JobFinishedStatus.TimeOut)
										.pipe(function(jobResultBlob) {
											return jobStateTools.setStatus(jobId, JobStatus.Finished, JobFinishedStatus.TimeOut)
												.then(function(_) {
													return jobResultBlob;
												});
										})
										.then(function(jobResultBlob) {
											finish(ProcessFinishReason.Timeout);
											return true;
										});
								} else {
									return writeJobResults(_redis, job, _remoteStorage, batchJobResult, batchJobResult.error != null ? JobFinishedStatus.Failed : JobFinishedStatus.Success)
										.pipe(function(jobResultBlob) {
											return jobStateTools.setStatus(jobId, JobStatus.Finished)
												.then(function(_) {
													return jobResultBlob;
												});
										})
										.then(function(jobResultBlob) {
											if (batchJobResult.error == null) {
												finish(ProcessFinishReason.Success(jobResultBlob.jobResult));
											} else {
												finish(ProcessFinishReason.Error(batchJobResult.error));
											}
											return true;
										});
								}
							}
						})
						.errorPipe(function(err) {
							log.error({error:err});
							//Write job as a failure
							//This should actually never happen, or the failure
							//should be handled
							var batchJobResult :BatchJobResult = {exitCode:-1, error:err, copiedLogs:false, timeout:false};
							// log.error({exitCode:-1, error:err, JobStatus:null, JobFinishedStatus:null});
							if (_isFinished) {
								return Promise.promise(true);
							} else {
								return writeJobResults(_redis, job, _remoteStorage, batchJobResult, JobFinishedStatus.Failed)
									.pipe(function(jobResultBlob) {
										return jobStateTools.setStatus(jobId, JobStatus.Finished, JobFinishedStatus.Failed, Json.stringify(err))
											.then(function(_) {
												return jobResultBlob;
											});
									})
									.then(function(jobResultBlob) {
										log.debug({job:job.jobId, message:"Finished writing job"});
										finish(ProcessFinishReason.Success(jobResultBlob.jobResult));
										return true;
									})
									.errorPipe(function(err) {
										finish(ProcessFinishReason.Error("Failed to write job results"));
										return Promise.promise(true);
									});
							}
						});
				})
				.errorPipe(function(err) {
					finish(ProcessFinishReason.Error(err));
					return Promise.promise(true);
				});
		} catch(e :Dynamic) {
			log.error({error:e, m:'FAILED JOB IN TRYCATCH'});
			finish(ProcessFinishReason.Error(e));
		}
	}
}