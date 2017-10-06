package ccc.compute.worker.job.state;

typedef JobStateUpdate = {
	var jobId :JobId;
	@:optional var attempt :Int;
	@:optional var state :JobStatus;
	@:optional var stateWorking :JobWorkingStatus;
	@:optional var stateFinished :JobFinishedStatus;
	@:optional var time :Float;
	@:optional var error :String;
}

@:build(t9.redis.RedisObject.build())
class JobStateTools
{
	inline static var PREFIX = '${JOBSPREFIX}state${SEP}';
	inline public static var REDIS_KEY_HASH_JOB_STATUS = '${PREFIX}hash${SEP}status';//<JobId, JobStatus>
	inline public static var REDIS_KEY_HASH_JOB_STATUS_WORKING = '${PREFIX}hash${SEP}status_working';//<JobId, JobWorkingStatus>
	inline public static var REDIS_KEY_HASH_JOB_STATUS_FINISHED = '${PREFIX}hash${SEP}status_finished';//<JobId, JobFinishedStatus>
	inline public static var REDIS_KEY_HASH_JOB_ERROR = '${PREFIX}hash${SEP}status_error';//<JobId, String>
	inline public static var REDIS_KEY_PREFIX_STATE_SET = '${PREFIX}set${SEP}status${SEP}';//Set<JobId>

	public static function getJobsWithStatus(status :JobStatus) :Promise<Array<JobId>>
	{
		return RedisPromises.smembers(REDIS_CLIENT, '${REDIS_KEY_PREFIX_STATE_SET}${status}')
			.then(function(result) {
				if (RedisLuaTools.isArrayObjectEmpty(result)) {
					return [];
				} else {
					return cast result;
				}
			});
	}

	static var SET_JOB_STATE_SCRIPT = '
	local JobStateUpdateString = ARGV[1]
	local JobStateUpdate = cjson.decode(JobStateUpdateString)
	local jobId = JobStateUpdate.jobId
	local state = JobStateUpdate.state
	local stateWorking = JobStateUpdate.stateWorking
	local attempt = JobStateUpdate.attempt
	local stateFinished = JobStateUpdate.stateFinished
	local time = JobStateUpdate.time
	local error = JobStateUpdate.error

	if state == "null" or state == "undefined" then state = nil end
	if stateWorking == "null" or stateWorking == "undefined" then stateWorking = nil end
	if stateFinished == "null" or stateFinished == "undefined" then stateFinished = nil end
	if error == "null" or error == "undefined" then error = nil end

	if not redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId) then
		return {err="${RedisError.NoJobFound}", script="SET_JOB_STATE_SCRIPT"}
	end

	local jobStatsJsonString = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId)
	local jobstats = cmsgpack.unpack(jobStatsJsonString)

	if jobstats.status == "${JobStatus.Finished}" then
		return {err="${RedisError.JobAlreadyFinished}", jobId=jobId, message="Job " .. jobId .. " already ${JobStatus.Finished}"}
	end

	if error ~= nil then
		redis.call("HSET", "${REDIS_KEY_HASH_JOB_ERROR}", jobId, error)
	end

	${JobStatsTools.SNIPPET_SAVE_STATUS_TO_STATS}

	return true
	';
	@redis({lua:'${SET_JOB_STATE_SCRIPT}'})
	public static function setJobStateInternalInternal(update :String) :Promise<Bool> {}
	public static function setJobStateInternal(update :JobStateUpdate) :Promise<Bool>
	{
		return setJobStateInternalInternal(Json.stringify(update));
	}

	static var SCRIPT_REMOVE_JOB =
	'
		local jobId = ARGV[1]
		redis.call("SREM", "${REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Pending}", jobId)
		redis.call("SREM", "${REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Working}", jobId)
		redis.call("SREM", "${REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Finished}", jobId)
		redis.call("HDEL", "${REDIS_KEY_HASH_JOB_STATUS}", jobId)
		redis.call("HDEL", "${REDIS_KEY_HASH_JOB_STATUS_WORKING}", jobId)
		redis.call("HDEL", "${REDIS_KEY_HASH_JOB_STATUS_FINISHED}", jobId)
		redis.call("HDEL", "${REDIS_KEY_HASH_JOB_ERROR}", jobId)
	';
	@redis({lua:'${SCRIPT_REMOVE_JOB}'})
	public static function removeJob(jobId :JobId) :Promise<Dynamic> {}



	static var SCRIPT_GET_STATUS =
	'
		local jobId = ARGV[1]
		local jobstatsString = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId)
		if jobstatsString then
			local jobstats = cmsgpack.unpack(jobstatsString)
			return jobstats.status
		else
			return {err="${RedisError.NoJobFound}", jobId=jobId}
		end
	';
	@redis({lua:'${SCRIPT_GET_STATUS}'})
	public static function getStatus(jobId :JobId) :Promise<JobStatus> {}

	public static function getStatuses() :Promise<Dynamic>
	{
		return RedisPromises.hgetall(REDIS_CLIENT, REDIS_KEY_HASH_JOB_STATUS);
	}

	public static function setStatus(jobId :JobId, status :JobStatus, ?finishedStatus :JobFinishedStatus, ?error :String) :Promise<Bool>
	{
		var update :JobStateUpdate = {
			jobId: jobId,
			state: status,
			stateFinished: finishedStatus,
			time: time(),
			error: error
		}
		return setJobStateInternal(update);
	}

	public static function setFinishedStatus(jobId :JobId, finishedStatus :JobFinishedStatus, ?error :String) :Promise<Bool>
	{
		var update :JobStateUpdate = {
			jobId: jobId,
			state: JobStatus.Finished,
			stateFinished: finishedStatus,
			time: time(),
			error: error
		}
		return setJobStateInternal(update);
	}

	static var SCRIPT_GET_WORKING_STATUS =
	'
		local jobId = ARGV[1]
		local jobstatsString = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId)
		if jobstatsString then
			local jobstats = cmsgpack.unpack(jobstatsString)
			local attemptVal = ARGV[2]
			local attempt
			if type(attemptVal) == "userdata" or tostring(attemptVal) == "null" then
				attempt = 1
			else
				attempt = tonumber(attemptVal)
			end

			local jobData = jobstats.attempts[attempt]
			if jobData then
				return jobData.statusWorking
			else
				return {err="${RedisError.NoAttemptFound}", message="job=" .. tostring(jobId) .. " no attempt " .. tostring(ARGV[2])}
			end
		else
			return {err="${RedisError.NoJobFound}", jobId=jobId}
		end
	';
	@redis({lua:'${SCRIPT_GET_WORKING_STATUS}'})
	public static function getWorkingStatus(jobId :JobId, ?attempt :Int) :Promise<JobWorkingStatus> {}

	public static function setWorkingStatus(jobId :JobId, attempt :Int, workingStatus :JobWorkingStatus) :Promise<Bool>
	{
		var update :JobStateUpdate = {
			jobId: jobId,
			attempt: attempt,
			stateWorking: workingStatus,
			time: time()
		}
		return setJobStateInternal(update);
	}

	public static function getFinishedStatus(jobId :JobId) :Promise<JobFinishedStatus>
	{
		return JobStatsTools.get(jobId)
			.then(function(jobStats) {
				return jobStats.statusFinished;
			});
	}

	public static function getJobError(jobId :JobId) :Promise<Dynamic>
	{
		return RedisPromises.hget(REDIS_CLIENT, REDIS_KEY_HASH_JOB_ERROR, jobId)
			.then(Json.parse);
	}

	static var SNIPPET_JOB_CANCEL = '
	redis.log(redis.LOG_NOTICE, "SNIPPET_JOB_CANCEL")
	redis.log(redis.LOG_NOTICE, "redis.call(HEXISTS, ${REDIS_KEY_HASH_JOB_STATS}, " .. jobId .. ")")
	redis.log(redis.LOG_NOTICE, redis.call("HEXISTS", "${REDIS_KEY_HASH_JOB_STATS}", jobId))
	redis.log(redis.LOG_NOTICE, type(redis.call("HEXISTS", "${REDIS_KEY_HASH_JOB_STATS}", jobId)))
	if redis.call("HEXISTS", "${REDIS_KEY_HASH_JOB_STATS}", jobId) == 0 then
		return {err="${RedisError.NoJobFound}", jobId=jobId, script="SNIPPET_JOB_CANCEL"}
	end
	${JobStatsTools.SNIPPET_LOAD_CURRENT_JOB_STATS}
	local state = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATUS}", jobId)
	redis.log(redis.LOG_NOTICE, "state=" .. tostring(state))
	if state then
		if state == "${JobStatus.Finished}" then
			return
		end
		local stateWorking = "${JobWorkingStatus.Cancelled}"
		local stateFinished = "${JobFinishedStatus.Killed}"
		state = "${JobStatus.Finished}"
		redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATUS}", jobId, state)
		redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATUS_WORKING}", jobId, stateWorking)
		redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATUS_FINISHED}", jobId, stateFinished)
		local attempts = jobstats.attempts
		local attempt = #attempts
		${JobStatsTools.SNIPPET_SAVE_STATUS_TO_STATS}

		local logMessage = {level="info", message="Job cancelled", jobId=jobId}
		${RedisLoggerTools.SNIPPET_REDIS_LOG}
	else
		local logMessage = {level="debug", message="Job cancel, but no job exists", jobId=jobId}
		${RedisLoggerTools.SNIPPET_REDIS_LOG}
	end
	';

	static var SCRIPT_JOB_CANCELLED =
	'
		local jobId = ARGV[1]
		local time = tonumber(ARGV[2])
		${SNIPPET_JOB_CANCEL}
	';
	@redis({lua:'${SCRIPT_JOB_CANCELLED}'})
	static function cancelJobInternal(jobId :JobId, time :Float) :Promise<Bool> {}
	public static function cancelJob(jobId :JobId) :Promise<Bool>
	{
		return cancelJobInternal(jobId, time());
	}


	static var SCRIPT_JOB_CANCEL_ALL =
	'
		local time = tonumber(ARGV[1])
		local activeJobIds = redis.call("ZRANGE", "${JobStatsTools.REDIS_ZSET_JOBS_ACTIVE}", 0, -1)

		for i,jobId in ipairs(activeJobIds) do
			redis.log(redis.LOG_NOTICE, "Cancelling job (from cancel all)" .. tostring(jobId))
			local logMessage = {level="${RedisLoggerTools.REDIS_LOG_WARN}", message="Cancelling job (from cancel all)", jobId=jobId}
			${RedisLoggerTools.SNIPPET_REDIS_LOG}
			if redis.call("HEXISTS", "${REDIS_KEY_HASH_JOB_STATS}", jobId) == 1 then
				${SNIPPET_JOB_CANCEL}
			end
		end
	';
	@redis({lua:'${SCRIPT_JOB_CANCEL_ALL}'})
	static function cancelAllJobsInternal(time :Float) :Promise<Bool> {}
	public static function cancelAllJobs() :Promise<Bool>
	{
		var queue = new js.npm.bull.Bull.Queue(BullQueueNames.JobQueue, {redis:{port:REDIS_CLIENT.connection_options.port, host:REDIS_CLIENT.connection_options.host}});
		return queue.empty().promhx()
			.then(function(status) {
				traceCyan('Emptied queue=${BullQueueNames.JobQueue}');
				traceCyan(status);
				queue.close();
				return true;
			})
			.pipe(function(_) {
				traceCyan('cancelAllJobsInternal');
				return cancelAllJobsInternal(time());
			});
	}

	public static function jsonify() :Promise<Dynamic>
	{
		return RedisPromises.hgetall(REDIS_CLIENT, REDIS_KEY_HASH_JOB_STATUS)
			.pipe(function(allStatus) {
				return RedisPromises.hgetall(REDIS_CLIENT, REDIS_KEY_HASH_JOB_STATUS_WORKING)
					.then(function(allWorkingStatus) {
						return {
							status: allStatus,
							workingStatus: allWorkingStatus
						};
					});
			});
	}

	inline static function time() :Float
	{
		return Date.now().getTime();
	}
}
