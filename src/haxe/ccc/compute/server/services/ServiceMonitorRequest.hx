package ccc.compute.server.services;

/**
 * Health checks against the system need to verify all the components are
 * working, but also return quickly, without an undue burden on the system.
 * So we need special handing for these checks:
 *
 *  - When the /test API is hit, the stack checks if a job successfully
 *    finished executing in the last two minutes (or some other sensible
 *    interval). This successful job (not necessarily a test job) is used
 *    as evidence that the stack is working, and a healthy response is
 *    returned. No actual test job is run.
 *
 *  - Otherwise, if there is a currently executing /test job, the response
 *     will wait for that job to finish executing, and use those results
 *     for the response (so only one test job ever needs to be run
 *     concurrently).
 *
 *  - Otherwise, if the queue is empty AND there are available worker slots,
 *    the test job is added to the front of the regular queue.
 *
 *  - Otherwise, the priority queue is used. This can put additional load
 *    on a worker, but since the test job is designed to execute quickly,
 *    the additional load on the worker should be minimal (and there will
 *    only ever be a single test job running).
 *
 *    Debugging:
 *     - haxe compiler flags:
 *       - ENABLE_LOG_ServiceMonitorRequest
 */

@:enum
abstract ServiceMonitorRequestSuccessReason(String) to String {
	var AnotherJobFinishedRecently = 'AnotherJobFinishedRecently';
	var AnotherJobFinishedRecentlyWithoutWaiting = 'AnotherJobFinishedRecentlyWithoutWaiting';
	var TestJobFinishedRecentlyWithoutWaiting = 'TestJobFinishedRecentlyWithoutWaiting';
	var TestJobFinishedRecently = 'TestJobFinishedRecently';
	var FailedTimedOut = 'FailedTimedOut';
	var Unknown = 'Unknown';
	var Testing = 'Testing';
}
typedef ServiceMonitorRequestResult = {
	var OK :Bool;
	var reason: ServiceMonitorRequestSuccessReason;
	@:optional var error :Dynamic;
	@:optional var debug :Dynamic;
	var within :Float;
	var maxWithin :Float;
	@:optional var job :Dynamic;
}
typedef ServiceMonitorLastSuccessfulJob = {
	var jobId :JobId;
	var time :Float;
	var meta :Dynamic;
}

typedef ServiceMonitorArgs = {
	@:optional var within :Float;
}

class ServiceMonitorRequest
{
	inline public static var ROUTE_MONITOR = '/monitor';
	inline public static var ROUTE_MONITOR_JOB_COUNT = '/monitor/jobcount';

	@inject('StatusStream') public var _JOB_STREAM :Stream<JobStatsData>;
	@inject public var redis :RedisClient;
	@inject public var injector :Injector;

	var log :AbstractLogger;

	public function monitor(?args :ServiceMonitorArgs) :Promise<ServiceMonitorRequestResult>
	{
#if ENABLE_LOG_ServiceMonitorRequest
		traceYellow('monitor request main');
#end
		var now = Date.now().getTime();
		var jobId :JobId;

		var maxWithin = args != null && args.within != null ? args.within : ServerConfig.MONITOR_DEFAULT_JOB_COMPLETED_WITHIN * 1000;

		var result :ServiceMonitorRequestResult = {
			OK: true,
			reason: ServiceMonitorRequestSuccessReason.Unknown,
			debug: args,
			maxWithin: maxWithin,
			within: -1
		};

		if (_lastSuccessfulJobBlob != null && isWithinLastTimeInterval(now, _lastSuccessfulJobBlob.time, maxWithin)) {
			if (isOurJob(_lastSuccessfulJobBlob.meta)) {
				result.reason = ServiceMonitorRequestSuccessReason.TestJobFinishedRecentlyWithoutWaiting;
			} else {
				result.reason = ServiceMonitorRequestSuccessReason.AnotherJobFinishedRecentlyWithoutWaiting;
			}
			result.job = _lastSuccessfulJobBlob;
			result.within = now - _lastSuccessfulJobBlob.time;
			return Promise.promise(result);
		}

		var promise = new DeferredPromise();
		var toReturn = promise.boundPromise;
		var localSuccessfulJobListener;
		var timerId :Dynamic;

		var cleanup = function() {
			promise = null;
			if (timerId != null) {
				Node.clearTimeout(timerId);
				timerId = null;
			}
			if (localSuccessfulJobListener != null) {
				localSuccessfulJobListener.end();
				localSuccessfulJobListener = null;
			}
		}

		//After the maximum time allowed (plus a second), fail the request
		timerId = Node.setTimeout(function() {
			if (promise != null) {
				result.OK = false;
				result.reason = ServiceMonitorRequestSuccessReason.FailedTimedOut;
				promise.boundPromise.reject(result);
			}
			cleanup();
		}, Std.int(30000));

		//Immediately return if any job succeeds in the meanwhile
		localSuccessfulJobListener = _jobSuccessStream.then(function(jobBlob) {
			if (jobBlob != null) {
				if (promise != null) {
					if (isWithinLastTimeInterval(now, jobBlob.time, maxWithin)) {
						result.reason = ServiceMonitorRequestSuccessReason.AnotherJobFinishedRecently;
						result.job = jobBlob;
						result.within = jobBlob.time > now ? jobBlob.time - now : now - jobBlob.time;
						promise.resolve(result);
						cleanup();
					}
				} else if (localSuccessfulJobListener != null) {
					localSuccessfulJobListener.end();
					localSuccessfulJobListener = null;
				}
			}
		});

		getAllRunningTestJobs()
			.pipe(function(jobIds) {
				if (jobIds.length > 0) {
#if ENABLE_LOG_ServiceMonitorRequest
					traceYellow('not creating another test job, waiting on an already submitted one, current monitor jobs=$jobIds');
#end
					return Promise.promise(true);
				} else {
					if (promise != null) {
#if ENABLE_LOG_ServiceMonitorRequest
						traceYellow('No existing test jobs, creating one now');
#end
						var shortTestJob = createShortTestJob('monitor');
						return ClientJSTools.postJob('localhost:${ServerConfig.PORT}', shortTestJob)
							.then(function(job) {
								jobId = job.jobId;
#if ENABLE_LOG_ServiceMonitorRequest
								traceYellow('Submitted job=$jobId');
#end
								return true;
							});
					} else {
						return Promise.promise(true);
					}
				}
			});

		return toReturn;
	}

	public function getAllRunningTestJobs() :Promise<Array<JobId>>
	{
		return JobStatsTools.getActiveJobsForKeyword(JOB_MONITOR_KEYWORD);
	}

	@post
	public function postInject()
	{
		log = Log.child({cls: ServiceMonitorRequest});
		//Keep a tally of the last successful jobs
		_jobSuccessStream = _JOB_STREAM.then(function(jobStats) {
			if (jobStats != null) {
				// traceCyan(Json.stringify(jobStats, null, '  '));
				//If this is one of our jobs, after a while, remove all traces of it
				// if (jobStats.def != null && isOurJob(jobStats.def.meta)) {
				// 	Node.setTimeout(function() {
				// 		JobCommands.deleteJobFiles(injector, jobStats.jobId)
				// 			// .pipe(function(_) {
				// 			// 	JobStatsTools.removeJobStatsAll(jobStats.jobId)
				// 			// })
				// 			.catchError(function(err) {
				// 				Log.error({error:err, message: 'Error in deleting state test job files'});
				// 			});
				// 	}, 10000);
				// }

				//TODO: fix the error:"null" bug
				if (jobStats.status == JobStatus.Finished
					&& jobStats.attempts[jobStats.attempts.length - 1].exitCode == 0
					&& (jobStats.attempts[jobStats.attempts.length - 1].error == null || jobStats.attempts[jobStats.attempts.length - 1].error == "null")) {

					_lastSuccessfulJobBlob = {
						jobId: jobStats.jobId,
						time: jobStats.finished,
						meta: jobStats.def.meta
					};
#if ENABLE_LOG_ServiceMonitorRequest
					traceGreen('_lastSuccessfulJobBlob=${Json.stringify(_lastSuccessfulJobBlob)}');
#end
					return _lastSuccessfulJobBlob;
				}
			}
			return null;
		});
	}

	public static function init(injector :Injector)
	{
		var app = injector.getValue(js.npm.express.Application);
		var monitorHandler = new ServiceMonitorRequest();
		injector.map(ServiceMonitorRequest).toValue(monitorHandler);
		injector.injectInto(monitorHandler);
		app.get(ROUTE_MONITOR, function(req, res :js.npm.express.Response) {
#if ENABLE_LOG_ServiceMonitorRequest
			traceYellow('HIT MONITOR');
#end
			var query :DynamicAccess<String> = req.query;
			monitorHandler.monitor(cast query)
				.then(function(result) {
					res.json(result);
				})
				.catchError(function(err) {
					res.status(500).json(cast {error:err, success:false});
				});
		});

		app.get(ROUTE_MONITOR_JOB_COUNT, function(req, res :js.npm.express.Response) {
			monitorHandler.getAllRunningTestJobs()
				.then(function(jobIds) {
					res.json({count:jobIds.length});
				})
				.catchError(function(err) {
					res.status(500).json(cast {error:err, success:false});
				});
		});
	}

	var _lastSuccessfulJobBlob :ServiceMonitorLastSuccessfulJob;
	var _jobSuccessStream :Stream<ServiceMonitorLastSuccessfulJob>;

	public function new() {}

	inline static function isWithinLastTimeInterval(now :Float, jobTime :Float, maxWithin :Float) :Bool
	{
		return now < jobTime ?
			true
			:
			(jobTime > (now - maxWithin));
	}

	inline static function isOurJob(jobMeta :Dynamic) :Bool
	{
		return jobMeta != null
			&& Reflect.hasField(jobMeta, 'keywords')
			&& cast(Reflect.field(jobMeta, 'keywords'), Array<Dynamic>).has(JOB_META_TYPE);
	}

	static function createShortTestJob(testName :String) :BasicBatchProcessRequest
	{
		var TEST_BASE = 'tests';

		var inputName1 = 'in${ShortId.generate()}';
		var inputValueInline = 'in${ShortId.generate()}';

		var outputName1 = 'out${ShortId.generate()}';

		var inputInline :ComputeInputSource = {
			type: InputSource.InputInline,
			value: inputValueInline,
			name: inputName1
		}

		var scriptName = 'script.sh';
		var inputScript :ComputeInputSource = {
			type: InputSource.InputInline,
			value: '#!/bin/sh\ncat /$DIRECTORY_INPUTS/$inputName1 > /$DIRECTORY_OUTPUTS/$outputName1',
			name: scriptName
		}

		//Add the expected output name (we're not going to bother with content, too slow)
		var meta = {
			'name': testName,
			'type': JOB_META_TYPE,
			'expected': outputName1,
			'keywords': [JOB_MONITOR_KEYWORD]
		};

		var request: BasicBatchProcessRequest = {
			inputs: [inputInline, inputScript],
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'],
			meta: meta,
			appendStdOut: false,
			appendStdErr: false,
		}

		return request;
	}

	static var PREFIX = '${CCC_PREFIX}monitor${SEP}';
	static var REDIS_KEY_CURRENT_MONITOR_JOB = '${PREFIX}job';
	static var JOB_META_TYPE = 'monitor';
	static var JOB_MONITOR_KEYWORD = 'monitor';
}

