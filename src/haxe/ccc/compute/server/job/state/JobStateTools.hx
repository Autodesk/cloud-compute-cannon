package ccc.compute.server.job.state;

import js.npm.RedisClient;
import js.npm.redis.RedisLuaTools;

abstract JobStateTools(RedisClient) from RedisClient
{
	inline function new(r :RedisClient)
	{
		this = r;
	}

	inline public function init()
	{
		return JobStateScripts.init(this);
	}

	inline public function getStatusStream() :Stream<JobStatusUpdate>
	{
		var StatusStream :Stream<JobStatusUpdate> = RedisTools.createJsonStream(this, JobStateScripts.REDIS_CHANNEL_STATUS);
		StatusStream.catchError(function(err) {
			Log.error(err);
		});
		return StatusStream;
	}

	inline public function getJobsWithStatus(status :JobStatus) :Promise<Array<JobId>>
	{
		return RedisPromises.smembers(this, '${JobStateScripts.REDIS_KEY_PREFIX_STATE_SET}${status}')
			.then(function(result) {
				if (RedisLuaTools.isArrayObjectEmpty(result)) {
					return [];
				} else {
					return cast result;
				}
			});
	}

	inline public function removeJob(jobId :JobId) :Promise<Dynamic>
	{
		return JobStateScripts.evaluateLuaScript(this, JobStateScripts.SCRIPT_REMOVE_JOB, [jobId]);
	}

	inline public function getStatus(jobId :JobId) :Promise<JobStatus>
	{
		return RedisPromises.hget(this, JobStateScripts.REDIS_KEY_HASH_JOB_STATUS, jobId);
	}

	inline public function getStatuses() :Promise<Dynamic>
	{
		return RedisPromises.hgetall(this, JobStateScripts.REDIS_KEY_HASH_JOB_STATUS);
	}

	inline public function setStatus(jobId :JobId, status :JobStatus, ?finishedStatus :JobFinishedStatus, ?error :String) :Promise<Bool>
	{
		return JobStateScripts.evaluateLuaScript(this, JobStateScripts.SCRIPT_SET_JOB_STATES, [jobId, status, null, finishedStatus, error]);
	}

	inline public function getWorkingStatus(jobId :JobId) :Promise<JobWorkingStatus>
	{
		return RedisPromises.hget(this, JobStateScripts.REDIS_KEY_HASH_JOB_STATUS_WORKING, jobId);
	}

	inline public function setWorkingStatus(jobId :JobId, status :JobWorkingStatus) :Promise<Bool>
	{
		return JobStateScripts.evaluateLuaScript(this, JobStateScripts.SCRIPT_SET_JOB_STATES, [jobId, null, status, null, null]);
	}

	inline public function getFinishedStatus(jobId :JobId) :Promise<JobFinishedStatus>
	{
		return RedisPromises.hget(this, JobStateScripts.REDIS_KEY_HASH_JOB_STATUS_FINISHED, jobId);
	}

	inline public function getJobError(jobId :JobId) :Promise<Dynamic>
	{
		return RedisPromises.hget(this, JobStateScripts.REDIS_KEY_HASH_JOB_ERROR, jobId)
			.then(Json.parse);
	}

	inline public function cancelJob(jobId :JobId) :Promise<Bool>
	{
		return JobStateScripts.evaluateLuaScript(this, JobStateScripts.SCRIPT_JOB_CANCELLED, [jobId]);
	}

	inline public function jsonify() :Promise<Dynamic>
	{
		return RedisPromises.hgetall(this, JobStateScripts.REDIS_KEY_HASH_JOB_STATUS)
			.pipe(function(allStatus) {
				return RedisPromises.hgetall(this, JobStateScripts.REDIS_KEY_HASH_JOB_STATUS_WORKING)
					.then(function(allWorkingStatus) {
						return {
							status: allStatus,
							workingStatus: allWorkingStatus
						};
					});
			});
	}
}

class JobStateScripts
{
	inline static var PREFIX = '${CCC_PREFIX}job_state${SEP}';
	inline public static var REDIS_KEY_HASH_JOB_STATUS = '${PREFIX}status';//<JobId, JobStatus>
	inline public static var REDIS_KEY_HASH_JOB_STATUS_WORKING = '${PREFIX}status_working';//<JobId, JobWorkingStatus>
	inline public static var REDIS_KEY_HASH_JOB_STATUS_FINISHED = '${PREFIX}status_finished';//<JobId, JobFinishedStatus>
	inline public static var REDIS_KEY_HASH_JOB_ERROR = '${PREFIX}status_error';//<JobId, String>
	inline public static var REDIS_KEY_PREFIX_STATE_SET = '${PREFIX}status_set_';//Set<JobId>

	inline public static var REDIS_KEY_STATUS = '${PREFIX}job_status'; //Hash <JobId, JobStatus>
	inline public static var REDIS_CHANNEL_STATUS = '${PREFIX}job_status_channel'; //Publishes jobIds as they are timedout

	public static var SCRIPT_PUBLISH_JOB_STATE = '${PREFIX}publish_job_state';
	public static var SCRIPT_SET_JOB_STATES = '${PREFIX}set_job_states';
	public static var SCRIPT_REMOVE_JOB = '${PREFIX}remove_job_states';
	public static var SCRIPT_JOB_CANCELLED = '${PREFIX}cancel_job';

	static inline var SNIPPET_PUBLISH_STATUS = '
	local statusBlob = {}
	statusBlob.status = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATUS}", jobId)
	statusBlob.statusWorking = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATUS_WORKING}", jobId)
	statusBlob.statusFinished = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATUS_FINISHED}", jobId)
	statusBlob.jobId = jobId
	local statusBlobString = cjson.encode(statusBlob)
	redis.call("HSET", "$REDIS_KEY_STATUS", jobId, statusBlobString)
	redis.call("SET", "$REDIS_CHANNEL_STATUS", statusBlobString)
	redis.call("PUBLISH", "$REDIS_CHANNEL_STATUS", statusBlobString)
	';

	/* The literal Redis Lua scripts. These allow non-race condition and performant operations on the DB*/
	static var scripts :Map<String, String> = [
	SCRIPT_JOB_CANCELLED =>
	'
		local jobId = ARGV[1]
		local status = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATUS}", jobId)
		if status then
			local stateWorking
			local stateFinished
			if status == "${JobStatus.Pending}" or status == "${JobStatus.Working}" then
				stateWorking = "${JobWorkingStatus.Cancelled}"
				stateFinished = "${JobFinishedStatus.Killed}"
			elseif status == "${JobStatus.Finished}" then
				stateWorking = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATUS_WORKING}", jobId)
				stateFinished = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATUS_FINISHED}", jobId)
			end
			redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATUS}", jobId, status)
			redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATUS_WORKING}", jobId, stateWorking)
			redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATUS_FINISHED}", jobId, stateFinished)
		else
			print("Job already removed " .. jobId)
		end
	',
	SCRIPT_REMOVE_JOB =>
	'
		local jobId = ARGV[1]
		redis.call("SREM", "${REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Pending}", jobId)
		redis.call("SREM", "${REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Working}", jobId)
		redis.call("SREM", "${REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Finished}", jobId)
		redis.call("HDEL", "${REDIS_KEY_HASH_JOB_STATUS}", jobId)
		redis.call("HDEL", "${REDIS_KEY_HASH_JOB_STATUS_WORKING}", jobId)
		redis.call("HDEL", "${REDIS_KEY_HASH_JOB_STATUS_FINISHED}", jobId)
		redis.call("HDEL", "${REDIS_KEY_HASH_JOB_ERROR}", jobId)
	',
	SCRIPT_PUBLISH_JOB_STATE =>
	'
		local jobId = ARGV[1]
		$SNIPPET_PUBLISH_STATUS
	',
	SCRIPT_SET_JOB_STATES =>
	'
	local jobId = ARGV[1]
	local state = ARGV[2]
	local stateWorking = ARGV[3]
	local stateFinished = ARGV[4]
	local error = ARGV[5]

	if state == "null" then state = nil end
	if stateWorking == "null" then stateWorking = nil end
	if stateFinished == "null" then stateFinished = nil end
	if error == "null" then error = nil end

	if state ~= nil then
		if state == "${JobStatus.Finished}" and redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATUS}", jobId) == "${JobStatus.Finished}" then
			return redis.error_reply("Cannot set state to ${JobStatus.Finished} repeatedly")
		end

		redis.call("SREM", "${REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Pending}", jobId)
		redis.call("SREM", "${REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Working}", jobId)
		redis.call("SREM", "${REDIS_KEY_PREFIX_STATE_SET}${JobStatus.Finished}", jobId)
		redis.call("SADD", "${REDIS_KEY_PREFIX_STATE_SET}" .. state, jobId)

		redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATUS}", jobId, state)

		if state == "${JobStatus.Pending}" then
			stateWorking = "${JobWorkingStatus.None}"
			stateFinished = "${JobFinishedStatus.None}"
		end
	end

	if stateWorking ~= nil then
		redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATUS_WORKING}", jobId, stateWorking)
	end

	if stateFinished ~= nil then
		redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATUS_FINISHED}", jobId, stateFinished)
	end

	if error ~= nil then
		redis.call("HSET", "${REDIS_KEY_HASH_JOB_ERROR}", jobId, error)
	end

	$SNIPPET_PUBLISH_STATUS

	return true
',
	];

	/* When we call a Lua script, use the SHA of the already uploaded script for performance */
	static var SCRIPT_SHAS :Map<String, String>;
	static var SCRIPT_SHAS_TOIDS :Map<String, String>;

	public static function evaluateLuaScript<T>(redis :RedisClient, scriptKey :String, ?args :Array<Dynamic>) :Promise<T>
	{
		return RedisLuaTools.evaluateLuaScript(redis, SCRIPT_SHAS[scriptKey], null, args, SCRIPT_SHAS_TOIDS, scripts);
	}

	public static function init(redis :RedisClient) :Promise<Bool>//You can chain this to a series of piped promises
	{
		for (key in scripts.keys()) {
			var script = scripts.get(key);
			if (script.indexOf('local SCRIPTID') == -1) {
				script = 'local SCRIPTID = "$key"\n' + script;
				scripts.set(key, script);
			}
		}
		return RedisLuaTools.initLuaScripts(redis, scripts)
			.then(function(scriptIdsToShas :Map<String, String>) {
				SCRIPT_SHAS = scriptIdsToShas;
				//This helps with debugging the lua scripts, uses the name instead of the hash
				SCRIPT_SHAS_TOIDS = new Map();
				for (key in SCRIPT_SHAS.keys()) {
					SCRIPT_SHAS_TOIDS[SCRIPT_SHAS[key]] = key;
				}
				return SCRIPT_SHAS != null;
			});
	}
}