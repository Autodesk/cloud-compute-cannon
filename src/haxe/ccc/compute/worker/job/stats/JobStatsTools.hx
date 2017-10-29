package ccc.compute.worker.job.stats;

import util.DateFormatTools;
/**
 * Values stored here are not removed when the job data is removed, since
 * they are needed for health monitoring etc. This data is only removed
 * via expiring old data.
 */
@:build(t9.redis.RedisObject.build())
class JobStatsTools
{
	static var PREFIX = '${JOBSPREFIX}${SEP}stats${SEP}';
	public static var REDIS_KEY_ZSET_PREFIX_WORKER_JOBS = '${JOBSPREFIX}zset${SEP}worker_jobs${SEP}';//<JobId>
	public static var REDIS_KEY_ZSET_PREFIX_WORKER_JOBS_ACTIVE = '${JOBSPREFIX}zset${SEP}worker_jobs_active${SEP}';//<JobId>
	public static var REDIS_KEY_HASH_JOB_WORKER = '${JOBSPREFIX}hash${SEP}jobid_to_workerid';//<JobId, MachineId>
	public static var REDIS_ZSET_JOBS_ACTIVE = '${PREFIX}zset${SEP}jobs_active';
	/* Yes I need a sorted set AND a set because you cannot do intersections between types */
	public static var REDIS_SET_JOBS_ACTIVE = '${PREFIX}set${SEP}jobs_active';
	static var REDIS_ZSET_JOBS_FINISHED = '${PREFIX}zset${SEP}jobs_finished';

	/* This channel has the JSONified entire job state */
	public static var REDIS_CHANNEL_JOB_PREFIX = '${JOBSPREFIX}channel${SEP}';
	/* This channel simply publishes the job Id of jobs whose state has changed */
	public static var REDIS_CHANNEL_STATUS = '${JOBSPREFIX}channel${SEP}status'; //Publishes jobIds as they are timedout
	/* This channel simply publishes the active jobIds of jobs whose state has changed */
	public static var REDIS_CHANNEL_JOBS_ACTIVE = '${JOBSPREFIX}channel${SEP}jobs_active';
	/* This channel simply publishes the list of finished jobIds in order of completion */
	public static var REDIS_CHANNEL_JOBS_FINISHED = '${JOBSPREFIX}channel${SEP}jobs_finished';

	public static var REDIS_JOB_INDEX_PREFIX = '${JOBSPREFIX}index${SEP}';

	static var SNIPPET_BAIL_IF_NO_JOB =
	'
	if redis.call("HEXISTS", "${REDIS_KEY_HASH_JOB_STATS}", jobId) == 0 then
		return
	end
	';

	public static var SNIPPET_LOAD_CURRENT_JOB_STATS =
	'
	local jobstats = cmsgpack.unpack(redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId))
	';

	static var SNIPPET_LOAD_CURRENT_JOB_ATTEMPT =
	'
	local jobData = jobstats.attempts[attempt]
	';

	static var SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA =
	'
	${SNIPPET_LOAD_CURRENT_JOB_STATS}
	${SNIPPET_LOAD_CURRENT_JOB_ATTEMPT}
	if not jobData then
		return {err="${RedisError.NoAttemptFound}", attempt=attempt, jobId=jobId, script="SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA"}
	end
	';

	public static var SNIPPET_PUBLISH_JOB = '
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		local jobstatsString = cjson.encode(jobstats)
		redis.call("SET", "$REDIS_CHANNEL_JOB_PREFIX" .. jobId, jobstatsString)
		redis.call("PUBLISH", "$REDIS_CHANNEL_JOB_PREFIX" .. jobId, jobstatsString)
		redis.call("PUBLISH", "$REDIS_CHANNEL_STATUS", jobId)
	';

	public static var SNIPPET_PUBLISH_ACTIVE_JOBS = '
		local sortedJobIds = redis.call("ZRANGE", "$REDIS_ZSET_JOBS_ACTIVE", 0, -1)
		local listString = "[]"
		if #sortedJobIds > 0 then
			listString = cjson.encode(sortedJobIds)
		end
		redis.call("PUBLISH", "$REDIS_CHANNEL_JOBS_ACTIVE", listString)
	';
	public static var SNIPPET_PUBLISH_FINISHED_JOBS = '
		local sortedJobIds = redis.call("ZRANGE", "$REDIS_ZSET_JOBS_FINISHED", 0, -1)
		local listString = "[]"
		if #sortedJobIds > 0 then
			listString = cjson.encode(sortedJobIds)
		end
		redis.call("PUBLISH", "$REDIS_CHANNEL_JOBS_FINISHED", listString)
	';

	static var SNIPPET_SAVE_JOB_STATS =
	'
	if jobstats.v then
		jobstats.v = jobstats.v + 1
	else
		jobstats.v = 1
	end
	redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATS}", jobId, cmsgpack.pack(jobstats))
	${SNIPPET_PUBLISH_JOB}
	';
	static var SNIPPET_REMOVE_JOB_META_INDICES =
	'
	$SNIPPET_LOAD_CURRENT_JOB_STATS
	local def = jobstats.def
	if def and def.meta and type(def.meta) ~= "userdata" and def.meta.keywords then
		local keywords = def.meta.keywords
		if type(keywords) == "table" then
			for k,v in ipairs(keywords) do
				local key1 = "${REDIS_JOB_INDEX_PREFIX}" .. tostring(k)
				local key2 = "${REDIS_JOB_INDEX_PREFIX}" .. tostring(v)
				redis.call("SREM", key1, jobId)
				redis.call("SREM", key2, jobId)
			end
		end
	end
	';

	/**
	 	Expects:
	 	local jobId = ARGV[1]
		local state = ARGV[2]
		local stateWorking = ARGV[3]
		local stateFinished = ARGV[4]
		local time = ARGV[5]
		local error = ARGV[6]
	 */
	public static var SNIPPET_SAVE_STATUS_TO_STATS =
	'
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		local jobData = jobstats.attempts[attempt]
		if not jobData then
			jobData = jobstats.attempts[#jobstats.attempts]
		end
		local publishActiveFinishedListChannel = false
		if state ~= nil then
			if state == "${JobStatus.Finished}" then

				if jobstats.status == "${JobStatus.Finished}" then
					return {err="jobId=" .. tostring(jobId) .. " Error setting status=" .. tostring(state) .. ", already finished"}
				end

				if jobData then
					jobData.finished = time
				end
				jobstats.finished = time

				publishActiveFinishedListChannel = true
				redis.call("ZREM", "${REDIS_ZSET_JOBS_ACTIVE}", jobId)
				redis.call("SREM", "${REDIS_SET_JOBS_ACTIVE}", jobId)
				redis.call("ZADD", "${REDIS_ZSET_JOBS_FINISHED}", time, jobId)

				local workerId = redis.call("HGET", "${REDIS_KEY_HASH_JOB_WORKER}", jobId)
				if workerId then
					redis.call("ZREM", "${REDIS_KEY_ZSET_PREFIX_WORKER_JOBS_ACTIVE}" .. workerId, jobId)
				end

				jobstats.statusFinished = stateFinished
				redis.call("HSET", "${JobStateTools.REDIS_KEY_HASH_JOB_STATUS_FINISHED}", jobId, stateFinished)

			elseif state == "${JobStatus.Pending}" and jobstats.status == "${JobStatus.Finished}" then
				return {err="jobId=" .. tostring(jobId) .. " Error setting status=" .. tostring(state) .. ", already ${JobStatus.Finished}"}
			elseif state == "${JobStatus.Working}" and jobstats.status == "${JobStatus.Finished}" then
				return {err="jobId=" .. tostring(jobId) .. " Error setting status=" .. tostring(state) .. ", already ${JobStatus.Finished}"}
			end

			redis.call("HSET", "${JobStateTools.REDIS_KEY_HASH_JOB_STATUS}", jobId, state)

			redis.call("SREM", "${JobStateTools.REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Pending}", jobId)
			redis.call("SREM", "${JobStateTools.REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Working}", jobId)
			redis.call("SREM", "${JobStateTools.REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Finished}", jobId)
			redis.call("SADD", "${JobStateTools.REDIS_KEY_PREFIX_STATE_SET}" .. state, jobId)

			jobstats.status = state
		end

		if stateWorking ~= nil then
			-- $ { SNIPPET_LOAD_CURRENT_JOB_ATTEMPT}
			if not jobData then
				return {err="${RedisError.NoAttemptFound}", attempt=attempt, jobId=jobId, script="SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA"}
			end
			jobData.statusWorking = stateWorking
			if error then
				jobData.error = error
			end
			jobstats.statusWorking = stateWorking
			redis.call("HSET", "${JobStateTools.REDIS_KEY_HASH_JOB_STATUS_WORKING}", jobId, stateWorking)
		end

		${SNIPPET_SAVE_JOB_STATS}
		if publishActiveFinishedListChannel then
			${SNIPPET_PUBLISH_ACTIVE_JOBS}
			${SNIPPET_PUBLISH_FINISHED_JOBS}
		end
	';

	public static function getActiveJobsForKeyword(keyword :String) :Promise<Array<JobId>>
	{
		var indexKey = '${REDIS_JOB_INDEX_PREFIX}${keyword}';
		return cast RedisPromises.sinter(REDIS_CLIENT, [indexKey, REDIS_SET_JOBS_ACTIVE]);
	}

	public static function getJobsForKeyword(keyword :String) :Promise<Array<JobId>>
	{
		return cast RedisPromises.smembers(REDIS_CLIENT, '${REDIS_JOB_INDEX_PREFIX}${keyword}');
	}

	@redis({lua:'
		local jobId = ARGV[1]
		${SNIPPET_BAIL_IF_NO_JOB}
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		return cjson.encode(jobstats)
	'})
	static function getInternal(jobId :JobId) :Promise<String> {}
	public static function get(jobId :JobId) :Promise<JobStatsData>
	{
		return getInternal(jobId)
			.then(function(dataString) {
				if (dataString != null) {
					return Json.parse(dataString);
				} else {
					return null;
				}
			});
	}

	public static function isJob(jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.hexists(REDIS_CLIENT, REDIS_KEY_HASH_JOB_STATS, jobId);
	}

	public static function toPretty(stats :JobStatsData)
	{
		var duration = DateFormatTools.getShortStringOfDateDiff(Date.fromTime(stats.requestReceived), Date.fromTime(stats.finished));
		var pretty :PrettyStatsData = {
			recieved: DateFormatTools.getFormattedDate(stats.requestReceived),
			duration: duration,
			uploaded: DateFormatTools.getShortStringOfDateDiff(Date.fromTime(stats.requestReceived), Date.fromTime(stats.requestUploaded)),
			finished: DateFormatTools.getFormattedDate(stats.finished),
			error: stats.error,
			attempts: stats.attempts.map(function(jobData) {
				var pending = DateFormatTools.getShortStringOfDateDiff(Date.fromTime(jobData.enqueued), Date.fromTime(jobData.dequeued));
				var timeMaxInputsImage = jobData.copiedImage > jobData.copiedInputs ? jobData.copiedImage : jobData.copiedInputs;
				var timeMaxOutputsLogs = jobData.copiedOutputs > jobData.copiedLogs ? jobData.copiedOutputs : jobData.copiedLogs;
				var jobDataPretty :PrettySingleJobExecution = {
					enqueued: DateFormatTools.getFormattedDate(jobData.enqueued),
					dequeued: DateFormatTools.getFormattedDate(jobData.dequeued),
					pending: pending,
					inputs: DateFormatTools.getShortStringOfDateDiff(Date.fromTime(jobData.dequeued), Date.fromTime(jobData.copiedInputs)),
					image: DateFormatTools.getShortStringOfDateDiff(Date.fromTime(jobData.dequeued), Date.fromTime(jobData.copiedImage)),
					inputsAndImage: DateFormatTools.getShortStringOfDateDiff(Date.fromTime(jobData.dequeued), Date.fromTime(timeMaxInputsImage)),
					container: DateFormatTools.getShortStringOfDateDiff(Date.fromTime(timeMaxInputsImage), Date.fromTime(jobData.containerExited)),
					outputs: DateFormatTools.getShortStringOfDateDiff(Date.fromTime(jobData.containerExited), Date.fromTime(jobData.copiedOutputs)),
					logs: DateFormatTools.getShortStringOfDateDiff(Date.fromTime(jobData.containerExited), Date.fromTime(jobData.copiedLogs)),
					outputsAndLogs: DateFormatTools.getShortStringOfDateDiff(Date.fromTime(jobData.containerExited), Date.fromTime(timeMaxOutputsLogs)),
					exitCode: jobData.exitCode,
					error: jobData.error
				};
				return jobDataPretty;
			}).array()
		};
		return pretty;
	}

	public static function getPretty(jobId :JobId) :Promise<PrettyStatsData>
	{
		return get(jobId)
			.then(function(stats :JobStatsData) {
				if (stats != null) {
					return toPretty(stats);
				} else {
					return null;
				}
			});
	}


	@redis({lua:'
		local jobId = ARGV[1]
		local time = tonumber(ARGV[2])
		local jobstats = {requestReceived=time, requestUploaded=0, finished=0, jobId=jobId}
		${SNIPPET_SAVE_JOB_STATS}
	'})
	static function requestRecievedInternal(jobId :JobId, time :Float) :Promise<String> {}
	public static function requestRecieved(jobId :JobId)
	{
		return requestRecievedInternal(jobId, time());
	}


	static var SCRIPT_REQUEST_UPLOAD_INTERNAL = '
	local jobId = ARGV[1]
	${SNIPPET_BAIL_IF_NO_JOB}
	local time = tonumber(ARGV[2])
	local jobstats = cmsgpack.unpack(redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId))
	jobstats["requestUploaded"] = time
	${SNIPPET_SAVE_JOB_STATS}
	';
	@redis({lua:'${SCRIPT_REQUEST_UPLOAD_INTERNAL}'})
	static function requestUploadedInternal(jobId :JobId, time :Float) :Promise<String> {}
	public static function requestUploaded(jobId :JobId)
	{
		return requestUploadedInternal(jobId, time());
	}

	static var JOB_ENQUEUED_INTERNAL_SCRIPT = '
	local jobId = ARGV[1]
	${SNIPPET_BAIL_IF_NO_JOB}
	local defString = ARGV[2]
	if defString then
		if defString == "null" then
			defString = nil
		end
		if defString == "nil" then
			defString = nil
		end
	end
	local time = tonumber(ARGV[3])
	local jobStatsJsonString = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId)
	local jobstats = nil
	if jobStatsJsonString then
		jobstats = cmsgpack.unpack(jobStatsJsonString)
	else
		--This can happen if the job is added without going through the request system
		jobstats = {requestReceived=time, requestUploaded=time, finished=0, jobId=jobId}
	end

	if jobstats.status == "${JobStatus.Finished}" then
		return redis.error_reply("Enqueuing but status==${JobStatus.Finished} jobId=" .. jobId)
	end

	jobstats.status = "${JobStatus.Pending}"

	local jobData = {enqueued=time,dequeued=0,copiedInputs=0,copiedImage=0,copiedInputsAndImage=0,containerExited=0,copiedOutputs=0}
	if jobstats.attempts == nil then
		jobstats.attempts = {}
	end
	if defString then
		local def = cjson.decode(defString)
		jobstats.def = def
		--Indexing
		if def and def.meta and type(def.meta) ~= "userdata" and def.meta.keywords then
			local keywords = def.meta.keywords
			if type(keywords) == "table" then
				for k,v in ipairs(keywords) do
					local key1 = "${REDIS_JOB_INDEX_PREFIX}" .. tostring(k)
					local key2 = "${REDIS_JOB_INDEX_PREFIX}" .. tostring(v)
					redis.call("SADD", key1, jobId)
					redis.call("SADD", key2, jobId)
					redis.log(redis.LOG_WARNING, "Added " .. jobId .. "to " .. key1 .. " and " .. key2)
				end
			end
		end
	else
		redis.log(redis.LOG_WARNING, "defString nil")
	end
	local attempt = #jobstats.attempts + 1
	jobstats.attempts[attempt] = jobData
	redis.call("ZADD", "${REDIS_ZSET_JOBS_ACTIVE}", time, jobId)
	redis.call("SADD", "${REDIS_SET_JOBS_ACTIVE}", jobId)

	--Remove worker<->job map if it exists
	local existingWorkerId = redis.call("HGET", "${REDIS_KEY_HASH_JOB_WORKER}", jobId)
	if existingWorkerId then
		redis.call("HDEL", "${REDIS_KEY_HASH_JOB_WORKER}", jobId)
		redis.call("ZREM", "${REDIS_KEY_ZSET_PREFIX_WORKER_JOBS_ACTIVE}" .. existingWorkerId, jobId)
	end

	${SNIPPET_SAVE_JOB_STATS}
	${SNIPPET_PUBLISH_ACTIVE_JOBS}

	return attempt
	';
	@redis({lua:'${JOB_ENQUEUED_INTERNAL_SCRIPT}'})
	static function jobEnqueuedInternal(jobId :JobId, def :String, time :Float) :Promise<Int> {}
	public static function jobEnqueued(jobId :JobId, def :DockerBatchComputeJob)
	{
		return jobEnqueuedInternal(jobId, def != null ? Json.stringify(def) : "null", time());
	}

	static var SCRIPT_DEQUEUED_INTERNAL = '
	local jobId = ARGV[1]
	local attempt = tonumber(ARGV[2])
	local workerId = ARGV[3]
	${SNIPPET_BAIL_IF_NO_JOB}
	local time = tonumber(ARGV[4])
	redis.call("ZADD", "${REDIS_KEY_ZSET_PREFIX_WORKER_JOBS}" .. workerId, time, jobId)

	local existingWorkerId = redis.call("HGET", "${REDIS_KEY_HASH_JOB_WORKER}", jobId)
	if existingWorkerId then
		redis.call("ZREM", "${REDIS_KEY_ZSET_PREFIX_WORKER_JOBS_ACTIVE}" .. existingWorkerId, jobId)
	end
	redis.call("ZADD", "${REDIS_KEY_ZSET_PREFIX_WORKER_JOBS_ACTIVE}" .. workerId, time, jobId)
	redis.call("HSET", "${REDIS_KEY_HASH_JOB_WORKER}", jobId, workerId)
	${SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA}
	jobData.dequeued = time
	jobData.worker = workerId
	${SNIPPET_SAVE_JOB_STATS}
	';
	@redis({lua:'${SCRIPT_DEQUEUED_INTERNAL}'})
	static function jobDequeuedInternal(jobId :JobId, attempt :Int, workerId :MachineId, time :Float) :Promise<String> {}
	public static function jobDequeued(jobId :JobId, attempt :Int, workerId :MachineId)
	{
		return jobDequeuedInternal(jobId, attempt, workerId, time());
	}

	@redis({lua:'
		local jobId = ARGV[1]
		${SNIPPET_BAIL_IF_NO_JOB}
		local attempt = tonumber(ARGV[2])
		local time = tonumber(ARGV[3])
		${SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA}
		jobData.copiedInputs = time
		${SNIPPET_SAVE_JOB_STATS}
	'})
	static function jobCopiedInputsInternal(jobId :JobId, attempt :Int, time :Float) :Promise<String> {}
	public static function jobCopiedInputs(jobId :JobId, attempt :Int)
	{
		return jobCopiedInputsInternal(jobId, attempt, time());
	}

	@redis({lua:'
		local jobId = ARGV[1]
		${SNIPPET_BAIL_IF_NO_JOB}
		local attempt = tonumber(ARGV[2])
		local time = tonumber(ARGV[3])
		${SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA}
		jobData.copiedImage = time
		${SNIPPET_SAVE_JOB_STATS}
	'})
	static function jobCopiedImageInternal(jobId :JobId, attempt :Int, time :Float) :Promise<String> {}
	public static function jobCopiedImage(jobId :JobId, attempt :Int)
	{
		return jobCopiedImageInternal(jobId, attempt, time());
	}

	@redis({lua:'
		local jobId = ARGV[1]
		${SNIPPET_BAIL_IF_NO_JOB}
		local attempt = tonumber(ARGV[2])
		local time = tonumber(ARGV[3])
		${SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA}
		jobData.copiedInputsAndImage = time
		${SNIPPET_SAVE_JOB_STATS}
	'})
	static function jobCopiedInputsAndImageInternal(jobId :JobId, attempt :Int, time :Float) :Promise<String> {}
	public static function jobCopiedInputsAndImage(jobId :JobId, attempt :Int)
	{
		return jobCopiedInputsAndImageInternal(jobId, attempt, time());
	}

	static var SCRIPT_SET_CONTAINER =
	'
		local jobId = ARGV[1]
		${SNIPPET_BAIL_IF_NO_JOB}
		local attempt = tonumber(ARGV[2])
		local containerId = ARGV[3]
		${SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA}
		jobData.containerId = containerId
		${SNIPPET_SAVE_JOB_STATS}
	';
	@redis({lua:'${SCRIPT_SET_CONTAINER}'})
	public static function setJobContainer(jobId :JobId, attempt :Int, containerId :DockerContainerId) :Promise<Bool> {}

	static var SCRIPT_GET_CONTAINER =
	'
		local jobId = ARGV[1]
		${SNIPPET_BAIL_IF_NO_JOB}
		local attempt = tonumber(ARGV[2])
		${SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA}
		return jobData.containerId
	';
	@redis({lua:'${SCRIPT_GET_CONTAINER}'})
	public static function getJobContainer(jobId :JobId, attempt :Int) :Promise<DockerContainerId> {}

	@redis({lua:'
		local jobId = ARGV[1]
		${SNIPPET_BAIL_IF_NO_JOB}
		local attempt = tonumber(ARGV[2])
		local time = tonumber(ARGV[3])
		local exitCode = tonumber(ARGV[4])
		local error = ARGV[5]
		${SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA}
		jobData.containerExited = time
		jobData.exitCode = exitCode
		jobData.error = error
		${SNIPPET_SAVE_JOB_STATS}
	'})
	static function jobContainerExitedInternal(jobId :JobId, attempt :Int, time :Float, exitCode :Int, ?error :String) :Promise<String> {}
	public static function jobContainerExited(jobId :JobId, attempt :Int, exitCode :Int, ?error :String)
	{
		return jobContainerExitedInternal(jobId, attempt, time(), exitCode, error);
	}

	@redis({lua:'
		local jobId = ARGV[1]
		${SNIPPET_BAIL_IF_NO_JOB}
		local attempt = tonumber(ARGV[2])
		local time = tonumber(ARGV[3])
		${SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA}
		jobData.copiedOutputs = time
		${SNIPPET_SAVE_JOB_STATS}
	'})
	static function jobCopiedOutputsInternal(jobId :JobId, attempt :Int, time :Float) :Promise<String> {}
	public static function jobCopiedOutputs(jobId :JobId, attempt :Int)
	{
		return jobCopiedOutputsInternal(jobId, attempt, time());
	}

	@redis({lua:'
		local jobId = ARGV[1]
		${SNIPPET_BAIL_IF_NO_JOB}
		local attempt = tonumber(ARGV[2])
		local time = tonumber(ARGV[3])
		${SNIPPET_LOAD_CURRENT_JOB_STATS_AND_DATA}
		jobData.copiedLogs = time
		${SNIPPET_SAVE_JOB_STATS}
	'})
	static function jobCopiedLogsInternal(jobId :JobId, attempt :Int, time :Float) :Promise<String> {}
	public static function jobCopiedLogs(jobId :JobId, attempt :Int)
	{
		return jobCopiedLogsInternal(jobId, attempt, time());
	}

	static var SNIPPET_REMOVE_ALL_JOB_TRACES = '
	local machineId = redis.call("HGET", "${REDIS_KEY_HASH_JOB_WORKER}", jobId)
	if machineId then
		local workerJobsKey = "${REDIS_KEY_ZSET_PREFIX_WORKER_JOBS}" .. machineId
		local workerJobsActiveKey = "${REDIS_KEY_ZSET_PREFIX_WORKER_JOBS_ACTIVE}" .. machineId
		redis.call("ZREM", workerJobsKey, jobId)
		redis.call("ZREM", workerJobsActiveKey, jobId)
	end
	redis.call("ZREM", "$REDIS_ZSET_JOBS_ACTIVE}", jobId)
	redis.call("ZREM", "$REDIS_ZSET_JOBS_FINISHED}", jobId)
	redis.call("SREM", "$REDIS_SET_JOBS_ACTIVE}", jobId)
	${SNIPPET_REMOVE_JOB_META_INDICES}
	redis.log(redis.LOG_WARNING, "Deleting job stats blob for jobId=" .. jobId)
	redis.call("HDEL", "${REDIS_KEY_HASH_JOB_STATS}", jobId)
	';
	static var SCRIPT_REMOVE_ALL_JOBS_TRACES = '
	local jobId = ARGV[1]
	$SNIPPET_REMOVE_ALL_JOB_TRACES
	';
	@redis({lua:'${SCRIPT_REMOVE_ALL_JOBS_TRACES}'})
	public static function removeJobStatsAll(jobId :JobId) :Promise<Bool> {}

	static var SCRIPT_REMOVE_ALL_JOBS_TRACES_ALL = '
	local jobIds = redis.call("HKEYS", "${REDIS_KEY_HASH_JOB_STATS}")
	for k,jobId in ipairs(jobIds) do
		${SNIPPET_REMOVE_ALL_JOB_TRACES}
	end
	';
	@redis({lua:'${SCRIPT_REMOVE_ALL_JOBS_TRACES_ALL}'})
	public static function removeAllJobsStatsAll() :Promise<Bool> {}

	static var SCRIPT_GET_ATTEMPTS = '
	local jobId = ARGV[1]
	if redis.call("HEXISTS", "${REDIS_KEY_HASH_JOB_STATS}", jobId) == 0 then
		return 0
	else
		local jobstats = cmsgpack.unpack(redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId))
		return #jobstats.attempts
	end
	';
	@redis({lua:'${SCRIPT_GET_ATTEMPTS}'})
	public static function getAttempts(jobId :JobId) :Promise<Int> {}


	static var SCRIPT_GET_JOB_STATE_INTERNAL = '
	local allJobStats = redis.call("HGETALL", "${REDIS_KEY_HASH_JOB_STATS}")
	local allJobsMap = {}
	local index = 1
	while allJobStats[index] do
		local jobStats = cmsgpack.unpack(allJobStats[index + 1])
		allJobsMap[jobStats.jobId] = jobStats
		index = index + 2
	end
	local sortedActiveJobIds = redis.call("ZRANGE", "$REDIS_ZSET_JOBS_ACTIVE", 0, -1)
	local sortedFinishedJobIds = redis.call("ZRANGE", "$REDIS_ZSET_JOBS_FINISHED", 0, -1)
	return cjson.encode({all=allJobsMap, active=sortedActiveJobIds, finished=sortedFinishedJobIds})
	';
	@redis({lua:'${SCRIPT_GET_JOB_STATE_INTERNAL}'})
	public static function getJobStateInternal() :Promise<String> {}
	public static function getJobState() :Promise<ccc.dashboard.state.JobsState>
	{
		return getJobStateInternal()
			.then(Json.parse)
			.then(function(jobstate :ccc.dashboard.state.JobsState) {
				//Stupid lua
				if (RedisLuaTools.isArrayObjectEmpty(jobstate.active)) {
					jobstate.active = [];
				}
				if (RedisLuaTools.isArrayObjectEmpty(jobstate.finished)) {
					jobstate.finished = [];
				}
				return jobstate;
			});
	}



	inline static function time() :Float
	{
		return Date.now().getTime();
	}
}
