package ccc.compute.server.job;

import js.npm.RedisClient;
import js.npm.redis.RedisLuaTools;

abstract Jobs(RedisClient) from RedisClient
{
	inline function new(r :RedisClient)
	{
		this = r;
	}

	inline public function init()
	{
		return JobScripts.init(this);
	}

	inline public function isJob(jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.hexists(this, JobScripts.REDIS_KEY_HASH_JOB, jobId);
	}

	inline public function getAllJobs() :Promise<Array<JobId>>
	{
		return cast RedisPromises.hkeys(this, JobScripts.REDIS_KEY_HASH_JOB);
	}

	inline public function getQueue() :Promise<Array<JobId>>
	{
		return cast RedisPromises.lrange(this, 'bull:${BullQueueNames.JobQueue}:wait', 0, -1);
	}

	inline public function getJob(jobId :JobId) :Promise<DockerBatchComputeJob>
	{
		return RedisPromises.hget(this, JobScripts.REDIS_KEY_HASH_JOB, jobId)
			.then(Json.parse);
	}

	inline public function setJob(jobId :JobId, job :DockerBatchComputeJob) :Promise<Bool>
	{
		return RedisPromises.hset(this, JobScripts.REDIS_KEY_HASH_JOB, jobId, Json.stringify(job))
			.thenTrue();
	}

	inline public function removeJob(jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.hdel(this, JobScripts.REDIS_KEY_HASH_JOB, jobId)
			.pipe(function(_) {
				return RedisPromises.hdel(this, JobScripts.REDIS_KEY_HASH_JOB_PARAMETERS, jobId);
			})
			.pipe(function(_) {
				return removeJobWorker(jobId);
			})
			.thenTrue();
	}

	inline public function getJobParameters(jobId :JobId) :Promise<JobParams>
	{
		return RedisPromises.hget(this, JobScripts.REDIS_KEY_HASH_JOB_PARAMETERS, jobId)
			.then(Json.parse);
	}

	inline public function setJobParameters(jobId :JobId, parameters :JobParams) :Promise<Bool>
	{
		return RedisPromises.hset(this, JobScripts.REDIS_KEY_HASH_JOB_PARAMETERS, jobId, Json.stringify(parameters))
			.thenTrue();
	}

	inline public function setJobWorker(jobId :JobId, workerId :MachineId) :Promise<Bool>
	{
		return RedisPromises.hset(this, JobScripts.REDIS_KEY_HASH_JOB_WORKER, jobId, workerId)
			.pipe(function(_) {
				return RedisPromises.sadd(this, JobScripts.REDIS_KEY_SET_PREFIX_WORKER_JOBS + workerId, [jobId]);
			})
			.thenTrue();
	}

	inline public function getJobsOnWorker(workerId :MachineId) :Promise<Array<JobId>>
	{
		return cast RedisPromises.smembers(this, JobScripts.REDIS_KEY_SET_PREFIX_WORKER_JOBS + workerId);
	}

	inline public function getAllWorkerJobs() :Promise<TypedDynamicObject<MachineId, Array<JobId>>>
	{
		return JobScripts.evaluateLuaScript(this, JobScripts.SCRIPT_GET_WORKER_JOBS)
			.then(function(jsonString) {
				var blob :TypedDynamicObject<MachineId, Array<JobId>> = Json.parse(jsonString);
				for (key in blob.keys()) {
					var val = blob.get(key);
					if (!untyped __js__('Array.isArray({0})', val)) {
						blob.set(key, []);
					}
				}
				return blob;
			});
	}

	inline public function removeJobWorker(jobId :JobId, ?worker :MachineId) :Promise<Bool>
	{
		return JobScripts.evaluateLuaScript(this, JobScripts.SCRIPT_REMOVE_JOB_WORKER, [jobId, worker])
			.thenTrue();
	}

	inline public function workersFailed(workerIds :Array<MachineId>) :Promise<Bool>
	{
		return JobScripts.evaluateLuaScript(this, JobScripts.SCRIPT_WORKERS_FAILED, [Json.stringify(workerIds)])
			.then(function(dataString) {
				traceMagenta('dataString=$dataString');
				return true;
			});
	}

	inline public function checkIfWorkersFailedIfSoRemoveJobs() :Promise<Bool>
	{
		return JobScripts.evaluateLuaScript(this, JobScripts.SCRIPT_CHECK_FOR_FAILED_WORKERS)
			.thenTrue();
	}
}

class JobScripts
{
	inline static var PREFIX = '${CCC_PREFIX}jobs${SEP}';
	inline public static var REDIS_KEY_HASH_JOB = '${PREFIX}job';//<JobId, DockerBatchComputeJob>
	inline public static var REDIS_KEY_HASH_JOB_PARAMETERS = '${PREFIX}parameters';//<JobId, JobParams>
	inline public static var REDIS_KEY_SET_PREFIX_WORKER_JOBS = '${PREFIX}worker_jobs${SEP}';//<JobId>
	inline public static var REDIS_KEY_HASH_JOB_WORKER = '${PREFIX}job_worker';//<JobId, MachineId>

	public static var SCRIPT_WORKERS_FAILED = '${PREFIX}workers_failed';
	public static var SCRIPT_REMOVE_JOB_WORKER = '${PREFIX}remove_job_worker';
	public static var SCRIPT_CHECK_FOR_FAILED_WORKERS = '${PREFIX}check_for_failed_workers';
	public static var SCRIPT_GET_WORKER_JOBS = '${PREFIX}get_all_worker_jobs';

	/* The literal Redis Lua scripts. These allow non-race condition and performant operations on the DB*/
	static var scripts :Map<String, String> = [
		SCRIPT_WORKERS_FAILED =>
		'
			local workerInstanceIdString = ARGV[1]
			if type(workerInstanceIdString) == "string" then
				local workerInstanceIds = cjson.decode(workerInstanceIdString)
				if workerInstanceIds and type(workerInstanceIds) == "table" then
					for _,instanceId in ipairs(workerInstanceIds) do
						redis.log(redis.LOG_WARNING, "  Removing jobs associated to " .. instanceId)
						local workerJobSetKey = "${REDIS_KEY_SET_PREFIX_WORKER_JOBS}" .. instanceId
						local jobsAssociatedWithInstance = redis.call("SMEMBERS", workerJobSetKey)
						if jobsAssociatedWithInstance then
							for _,jobId in ipairs(jobsAssociatedWithInstance) do
								redis.log(redis.LOG_WARNING, "Removing job " .. jobId .." associated to " .. instanceId)
								-- Make sure it is THIS instance we are removing the key for, the job may have been reassigned already
								if redis.call("HGET", "${REDIS_KEY_HASH_JOB_WORKER}", jobId) == instanceId then
									redis.call("HDEL", "${REDIS_KEY_HASH_JOB_WORKER}", jobId)
								end
							end
						end
						redis.call("DEL", workerJobSetKey)
					end
				end
			end
		',

		SCRIPT_REMOVE_JOB_WORKER =>
		'
			local jobId = ARGV[1]
			local workerId = ARGV[2]
			if not workerId then
				workerId = redis.call("HGET", "${REDIS_KEY_HASH_JOB_WORKER}", jobId)
			end
			if redis.call("HGET", "${REDIS_KEY_HASH_JOB_WORKER}", jobId) == workerId then
				redis.call("SREM", "${REDIS_KEY_SET_PREFIX_WORKER_JOBS}" .. workerId, jobId)
				redis.call("HDEL", "${REDIS_KEY_HASH_JOB_WORKER}", jobId)
			end
		',

		SCRIPT_CHECK_FOR_FAILED_WORKERS =>
		'
			local workerJobKeys = redis.call("KEYS", "${REDIS_KEY_SET_PREFIX_WORKER_JOBS}*")
			for _,key in ipairs(workerJobKeys) do
				local instanceId = string.gsub(key, "${REDIS_KEY_SET_PREFIX_WORKER_JOBS}", "")
				local workerHealthKey = "${WorkerCache.REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}" .. instanceId
				local healthStatus = redis.call("GET", workerHealthKey)
				if healthStatus ~= "${WorkerHealthStatus.OK}" then
					redis.log(redis.LOG_WARNING, "Instance " .. instanceId .. "=" .. tostring(healthStatus) .. " failed health check, removing jobs from instance in redis")
					local workerJobSetKey = "${REDIS_KEY_SET_PREFIX_WORKER_JOBS}" .. instanceId
					local jobsAssociatedWithInstance = redis.call("SMEMBERS", workerJobSetKey)
					if jobsAssociatedWithInstance then
						for _,jobId in ipairs(jobsAssociatedWithInstance) do
							redis.log(redis.LOG_WARNING, "Removing job " .. jobId .." associated to " .. instanceId)
							-- Make sure it is THIS instance we are removing the key for, the job may have been reassigned already
							if redis.call("HGET", "${REDIS_KEY_HASH_JOB_WORKER}", jobId) == instanceId then
								redis.call("HDEL", "${REDIS_KEY_HASH_JOB_WORKER}", jobId)
							end
						end
					end
					redis.call("DEL", workerJobSetKey)
				end
			end
		',

		SCRIPT_GET_WORKER_JOBS =>
		'
			local result = {}
			local workerHealthKeys = redis.call("KEYS", "${WorkerCache.REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}*")
			for _,workerHealthKey in ipairs(workerHealthKeys) do
				local instanceId = string.gsub(workerHealthKey, "${WorkerCache.REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}", "")
				local workerJobSetKey = "${REDIS_KEY_SET_PREFIX_WORKER_JOBS}" .. instanceId
				local jobsAssociatedWithInstance = redis.call("SMEMBERS", workerJobSetKey)
				if not jobsAssociatedWithInstance then
					jobsAssociatedWithInstance = {}
				end
				result[instanceId] = jobsAssociatedWithInstance
			end
			return cjson.encode(result)
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


