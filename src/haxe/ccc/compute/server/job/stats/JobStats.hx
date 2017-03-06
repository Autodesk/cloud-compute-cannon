package ccc.compute.server.job.stats;

import js.npm.RedisClient;
import js.npm.redis.RedisLuaTools;

import ccc.compute.server.job.stats.StatsDefinitions;

import util.DateFormatTools;

abstract JobStats(RedisClient) from RedisClient
{
	inline function new(r :RedisClient)
	{
		this = r;
	}

	inline public function init()
	{
		return JobStatsScripts.init(this);
	}

	inline public function get(jobId :JobId) :Promise<StatsData>
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_GET, [jobId])
			.then(function(dataString) {
				if (dataString != null) {
					return Json.parse(dataString);
				} else {
					return null;
				}
			});
	}

	inline public function getPretty(jobId :JobId) :Promise<PrettyStatsData>
	{
		return get(jobId)
			.then(function(stats :StatsData) {
				if (stats != null) {
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
				} else {
					return null;
				}
			});
	}

	inline public function requestRecieved(jobId :JobId)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_REQUEST_RECIEVED, [jobId, time()]);
	}

	inline public function requestUploaded(jobId :JobId)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_REQUEST_UPLOADED, [jobId, time()]);
	}

	inline public function jobFinished(jobId :JobId, ?error :String)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_FINISHED, [jobId, time(), error]);
	}

	inline public function jobEnqueued(jobId :JobId)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_ENQUEUED, [jobId, time()]);
	}

	inline public function jobDequeued(jobId :JobId)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_DEQUEUED, [jobId, time()]);
	}

	inline public function jobCopiedInputs(jobId :JobId)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_COPIED_INPUTS, [jobId, time()]);
	}

	inline public function jobCopiedImage(jobId :JobId)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_COPIED_IMAGE, [jobId, time()]);
	}

	inline public function jobCopiedInputsAndImage(jobId :JobId)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_COPIED_INPUTS_AND_IMAGE, [jobId, time()]);
	}

	inline public function jobContainerExited(jobId :JobId, exitCode :Int, ?error :String)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_CONTAINER_EXITED, [jobId, time(), exitCode, error]);
	}

	inline public function jobCopiedOutputs(jobId :JobId)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_COPIED_OUTPUTS, [jobId, time()]);
	}

	inline public function jobCopiedLogs(jobId :JobId)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_SET_JOB_COPIED_LOGS, [jobId, time()]);
	}

	inline public function removeJob(jobId :JobId)
	{
		return RedisPromises.hdel(this, JobStatsScripts.REDIS_KEY_HASH_JOB_STATS, jobId);
	}

	inline public function getAttempts(jobId :JobId)
	{
		return JobStatsScripts.evaluateLuaScript(this, JobStatsScripts.SCRIPT_GET_ATTEMPTS, [jobId]);
	}

	inline static function time() :Float
	{
		return Date.now().getTime();
	}
}

class JobStatsScripts
{
	public static var SCRIPT_SET_JOB_REQUEST_RECIEVED = '${PREFIX}job_request_recieved';
	public static var SCRIPT_SET_JOB_REQUEST_UPLOADED = '${PREFIX}job_request_uploaded';
	public static var SCRIPT_SET_JOB_FINISHED = '${PREFIX}job_finished';
	public static var SCRIPT_SET_JOB_ENQUEUED = '${PREFIX}job_enqueued';
	public static var SCRIPT_SET_JOB_DEQUEUED = '${PREFIX}job_dequeued';
	public static var SCRIPT_SET_JOB_COPIED_INPUTS = '${PREFIX}job_copied_inputs';
	public static var SCRIPT_SET_JOB_COPIED_IMAGE = '${PREFIX}job_copied_image';
	public static var SCRIPT_SET_JOB_COPIED_INPUTS_AND_IMAGE = '${PREFIX}job_copied_inputs_and_image';
	public static var SCRIPT_SET_JOB_CONTAINER_EXITED = '${PREFIX}job_container_exited';
	public static var SCRIPT_SET_JOB_COPIED_OUTPUTS = '${PREFIX}job_copied_outputs';
	public static var SCRIPT_SET_JOB_COPIED_LOGS = '${PREFIX}job_copied_logs';
	public static var SCRIPT_GET_ATTEMPTS = '${PREFIX}job_get_attempts';
	public static var SCRIPT_GET = '${PREFIX}job_get';

	public static var REDIS_KEY_HASH_JOB_STATS = '${CCC_PREFIX}job_stats_v2';

	static var SNIPPET_BAIL_IF_NO_JOB =
'
if redis.call("HEXISTS", "${REDIS_KEY_HASH_JOB_STATS}", jobId) == 0 then
	return
end
';

	static var SNIPPET_LOAD_CURRENT_JOB_STATS =
'
local jobstats = cmsgpack.unpack(redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId))
local jobData = jobstats.attempts[#jobstats.attempts]
';

	static var SNIPPET_SAVE_JOB_STATS =
'
redis.call("HSET", "${REDIS_KEY_HASH_JOB_STATS}", jobId, cmsgpack.pack(jobstats))
';


	/* The literal Redis Lua scripts. These allow non-race condition and performant operations on the DB*/
	static var scripts :Map<String, String> = [
		SCRIPT_GET_ATTEMPTS =>
		'
		local jobId = ARGV[1]
		if redis.call("HEXISTS", "${REDIS_KEY_HASH_JOB_STATS}", jobId) == 0 then
			return 0
		else
			local jobstats = cmsgpack.unpack(redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId))
			return #jobstats.attempts
		end
		',
		SCRIPT_SET_JOB_REQUEST_RECIEVED =>
		'
		local jobId = ARGV[1]
		local time = tonumber(ARGV[2])
		local jobstats = {requestReceived=time, requestUploaded=0, finished=0}
		${SNIPPET_SAVE_JOB_STATS}
		',

		SCRIPT_SET_JOB_REQUEST_UPLOADED =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		local time = tonumber(ARGV[2])
		local jobstats = cmsgpack.unpack(redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId))
		jobstats["requestUploaded"] = time
		${SNIPPET_SAVE_JOB_STATS}
		',

		SCRIPT_SET_JOB_FINISHED =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		local time = tonumber(ARGV[2])
		local error = ARGV[3]
		local jobstats = cmsgpack.unpack(redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId))
		jobstats["finished"] = time
		if error then
			jobstats["error"] = error
		end
		${SNIPPET_SAVE_JOB_STATS}
		',

		SCRIPT_SET_JOB_ENQUEUED =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		local time = tonumber(ARGV[2])
		local jobStatsJsonString = redis.call("HGET", "${REDIS_KEY_HASH_JOB_STATS}", jobId)
		local jobstats = nil
		if jobStatsJsonString then
			jobstats = cmsgpack.unpack(jobStatsJsonString)
		else
			--This can happen if the job is added without going through the request system
			jobstats = {requestReceived=time, requestUploaded=time, finished=0}
		end
		local jobData = {enqueued=time,dequeued=0,copiedInputs=0,copiedImage=0,copiedInputsAndImage=0,containerExited=0,copiedOutputs=0}
		if jobstats.attempts == nil then
			jobstats.attempts = {}
		end
		jobstats.attempts[#jobstats.attempts + 1] = jobData
		${SNIPPET_SAVE_JOB_STATS}
		',
		SCRIPT_SET_JOB_DEQUEUED =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		local time = tonumber(ARGV[2])
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		jobData.dequeued = time
		${SNIPPET_SAVE_JOB_STATS}
		',
		SCRIPT_SET_JOB_COPIED_INPUTS =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		local time = tonumber(ARGV[2])
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		jobData.copiedInputs = time
		${SNIPPET_SAVE_JOB_STATS}
		',
		SCRIPT_SET_JOB_COPIED_IMAGE =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		local time = tonumber(ARGV[2])
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		jobData.copiedImage = time
		${SNIPPET_SAVE_JOB_STATS}
		',
		SCRIPT_SET_JOB_COPIED_INPUTS_AND_IMAGE =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		local time = tonumber(ARGV[2])
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		jobData.copiedInputsAndImage = time
		${SNIPPET_SAVE_JOB_STATS}
		',
		SCRIPT_SET_JOB_CONTAINER_EXITED =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		local time = tonumber(ARGV[2])
		local exitCode = tonumber(ARGV[3])
		local error = ARGV[4]
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		jobData.containerExited = time
		jobData.exitCode = exitCode
		jobData.error = error
		${SNIPPET_SAVE_JOB_STATS}
		',
		SCRIPT_SET_JOB_COPIED_OUTPUTS =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		local time = tonumber(ARGV[2])
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		jobData.copiedOutputs = time
		${SNIPPET_SAVE_JOB_STATS}
		',
		SCRIPT_SET_JOB_COPIED_LOGS =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		local time = tonumber(ARGV[2])
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		jobData.copiedLogs = time
		${SNIPPET_SAVE_JOB_STATS}
		',
		SCRIPT_GET =>
		'
		local jobId = ARGV[1]
		$SNIPPET_BAIL_IF_NO_JOB
		${SNIPPET_LOAD_CURRENT_JOB_STATS}
		return cjson.encode(jobstats)
		',
	];

	/* When we call a Lua script, use the SHA of the already uploaded script for performance */
	static var SCRIPT_SHAS :Map<String, String>;
	static var SCRIPT_SHAS_TOIDS :Map<String, String>;
	inline static var PREFIX = 'job_stats${SEP}';

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
