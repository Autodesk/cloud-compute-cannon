package ccc.compute.worker.job;

import ccc.SharedConstants.*;

@:build(t9.redis.RedisObject.build())
class Jobs
{
	inline public static var REDIS_KEY_HASH_JOB = '${JOBSPREFIX}hash${SEP}definition';//<JobId, JobParams>
	inline public static var REDIS_KEY_HASH_JOB_PARAMETERS = '${JOBSPREFIX}hash${SEP}parameters';//<JobId, JobParams>

	public static function isJob(jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.hexists(REDIS_CLIENT, REDIS_KEY_HASH_JOB, jobId);
	}

	public static function getAllJobs() :Promise<Array<JobId>>
	{
		return cast RedisPromises.hkeys(REDIS_CLIENT, REDIS_KEY_HASH_JOB);
	}

	public static function getQueue() :Promise<Array<JobId>>
	{
		return cast RedisPromises.lrange(REDIS_CLIENT, 'bull:${BullQueueNames.JobQueue}:wait', 0, -1);
	}

	public static function getJob(jobId :JobId) :Promise<DockerBatchComputeJob>
	{
		return RedisPromises.hget(REDIS_CLIENT, REDIS_KEY_HASH_JOB, jobId)
			.then(Json.parse);
	}

	public static function setJob(jobId :JobId, job :DockerBatchComputeJob) :Promise<Bool>
	{
		return RedisPromises.hset(REDIS_CLIENT, REDIS_KEY_HASH_JOB, jobId, Json.stringify(job))
			.thenTrue();
	}

	public static function removeJob(jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.hdel(REDIS_CLIENT, REDIS_KEY_HASH_JOB, jobId)
			.pipe(function(_) {
				return RedisPromises.hdel(REDIS_CLIENT, REDIS_KEY_HASH_JOB_PARAMETERS, jobId);
			})
			.thenTrue();
	}

	public static function getJobParameters(jobId :JobId) :Promise<JobParams>
	{
		return RedisPromises.hget(REDIS_CLIENT, REDIS_KEY_HASH_JOB_PARAMETERS, jobId)
			.then(Json.parse);
	}

	public static function setJobParameters(jobId :JobId, parameters :JobParams) :Promise<Bool>
	{
		return RedisPromises.hset(REDIS_CLIENT, REDIS_KEY_HASH_JOB_PARAMETERS, jobId, Json.stringify(parameters))
			.thenTrue();
	}

	public static function getJobsOnWorker(workerId :MachineId) :Promise<Array<JobId>>
	{
		return cast RedisPromises.zrange(REDIS_CLIENT, JobStatsTools.REDIS_KEY_ZSET_PREFIX_WORKER_JOBS + workerId, 0, -1);
	}

	static var SCRIPT_GET_ALL_WORKER_JOB_INTERNAL = '
	local result = {}
	local workerHealthKeys = redis.call("KEYS", "${REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}*")
	for _,workerHealthKey in ipairs(workerHealthKeys) do
		local instanceId = string.gsub(workerHealthKey, "${REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}", "")
		local workerJobSetKey = "${JobStatsTools.REDIS_KEY_ZSET_PREFIX_WORKER_JOBS}" .. instanceId
		local jobsAssociatedWithInstance = redis.call("ZRANGE", workerJobSetKey, 0, -1)
		if not jobsAssociatedWithInstance then
			jobsAssociatedWithInstance = {}
		end
		result[instanceId] = jobsAssociatedWithInstance
	end
	return cjson.encode(result)
	';
	@redis({lua:'${SCRIPT_GET_ALL_WORKER_JOB_INTERNAL}'})
	static function getAllWorkerJobsInternal() :Promise<String>{}
	public static function getAllWorkerJobs() :Promise<TypedDynamicObject<MachineId, Array<JobId>>>
	{
		return getAllWorkerJobsInternal()
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


	static var SCRIPT_REMOVE_JOB_WORKER = '
	local jobId = ARGV[1]
	local workerId = ARGV[2]
	if not workerId then
		workerId = redis.call("HGET", "${JobStatsTools.REDIS_KEY_HASH_JOB_WORKER}", jobId)
	end
	if redis.call("HGET", "${JobStatsTools.REDIS_KEY_HASH_JOB_WORKER}", jobId) == workerId then
		redis.call("ZREM", "${JobStatsTools.REDIS_KEY_ZSET_PREFIX_WORKER_JOBS}" .. workerId, jobId)
		redis.call("HDEL", "${JobStatsTools.REDIS_KEY_HASH_JOB_WORKER}", jobId)
	end
	';
	@redis({lua:'${SCRIPT_REMOVE_JOB_WORKER}'})
	public static function removeJobWorker(jobId :JobId, ?worker :MachineId) :Promise<Bool> {}


	static var SCRIPT_WORKERS_FAILED_INTERNAL = '
	local workerInstanceIdString = ARGV[1]
	if type(workerInstanceIdString) == "string" then
		local workerInstanceIds = cjson.decode(workerInstanceIdString)
		if workerInstanceIds and type(workerInstanceIds) == "table" then
			for _,instanceId in ipairs(workerInstanceIds) do
				redis.log(redis.LOG_WARNING, "  Removing jobs associated to " .. instanceId)
				local workerJobSetKey = "${JobStatsTools.REDIS_KEY_ZSET_PREFIX_WORKER_JOBS}" .. instanceId
				local jobsAssociatedWithInstance = redis.call("ZRANGE", workerJobSetKey, 0, -1)
				if jobsAssociatedWithInstance then
					for _,jobId in ipairs(jobsAssociatedWithInstance) do
						redis.log(redis.LOG_WARNING, "Removing job " .. jobId .." associated to " .. instanceId)
						-- Make sure it is THIS instance we are removing the key for, the job may have been reassigned already
						if redis.call("HGET", "${JobStatsTools.REDIS_KEY_HASH_JOB_WORKER}", jobId) == instanceId then
							redis.call("HDEL", "${JobStatsTools.REDIS_KEY_HASH_JOB_WORKER}", jobId)
						end
					end
				end
				redis.call("DEL", workerJobSetKey)
			end
		end
	end
	';
	@redis({lua:'${SCRIPT_WORKERS_FAILED_INTERNAL}'})
	static function workersFailedInternal(workerIdsString :String) :Promise<String> {}
	public static function workersFailed(workerIds :Array<MachineId>) :Promise<Bool>
	{
		return workersFailedInternal(Json.stringify(workerIds))
			.then(function(dataString) {
				return true;
			});
	}

	static var SCRIPT_CHECK_IF_WORKERS_FAILED_IF_SO_REMOVE = '
	local workerJobKeys = redis.call("KEYS", "${JobStatsTools.REDIS_KEY_ZSET_PREFIX_WORKER_JOBS}*")
	for _,key in ipairs(workerJobKeys) do
		local instanceId = string.gsub(key, "${JobStatsTools.REDIS_KEY_ZSET_PREFIX_WORKER_JOBS}", "")
		local workerHealthKey = "${REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}" .. instanceId
		local healthStatus = redis.call("GET", workerHealthKey)
		if healthStatus ~= "${WorkerHealthStatus.OK}" then
			redis.log(redis.LOG_WARNING, "Instance " .. instanceId .. "=" .. tostring(healthStatus) .. " failed health check, removing jobs from instance in redis")
			local workerJobSetKey = "${JobStatsTools.REDIS_KEY_ZSET_PREFIX_WORKER_JOBS}" .. instanceId
			local jobsAssociatedWithInstance = redis.call("ZRANGE", workerJobSetKey, 0, -1)
			if jobsAssociatedWithInstance then
				for _,jobId in ipairs(jobsAssociatedWithInstance) do
					redis.log(redis.LOG_WARNING, "Removing job " .. jobId .." associated to " .. instanceId)
					-- Make sure it is THIS instance we are removing the key for, the job may have been reassigned already
					if redis.call("HGET", "${JobStatsTools.REDIS_KEY_HASH_JOB_WORKER}", jobId) == instanceId then
						redis.call("HDEL", "${JobStatsTools.REDIS_KEY_HASH_JOB_WORKER}", jobId)
					end
				end
			end
			redis.call("DEL", workerJobSetKey)
		end
	end
	';
	@redis({lua:'${SCRIPT_CHECK_IF_WORKERS_FAILED_IF_SO_REMOVE}'})
	public static function checkIfWorkersFailedIfSoRemoveJobs() :Promise<Bool> {}
}
