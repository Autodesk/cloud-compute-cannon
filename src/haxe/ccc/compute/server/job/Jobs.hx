package ccc.compute.server.job;

import js.npm.RedisClient;

abstract Jobs(RedisClient) from RedisClient
{
	inline static var PREFIX = '${CCC_PREFIX}jobs${SEP}';
	inline static var REDIS_KEY_HASH_JOB = '${PREFIX}job';//<JobId, DockerBatchComputeJob>
	inline static var REDIS_KEY_HASH_JOB_PARAMETERS = '${PREFIX}parameters';//<JobId, JobParams>
	inline static var REDIS_KEY_SET_PREFIX_WORKER_JOBS = '${PREFIX}worker_jobs';//<JobId>
	inline static var REDIS_KEY_HASH_JOB_WORKER = '${PREFIX}job_worker';//<JobId, MachineId>

	inline function new(r :RedisClient)
	{
		this = r;
	}

	inline public function init()
	{
		return Promise.promise(true);
	}

	inline public function isJob(jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.hexists(this, REDIS_KEY_HASH_JOB, jobId);
	}

	inline public function getAllJobs() :Promise<Array<JobId>>
	{
		return cast RedisPromises.hkeys(this, REDIS_KEY_HASH_JOB);
	}

	inline public function getJob(jobId :JobId) :Promise<DockerBatchComputeJob>
	{
		return RedisPromises.hget(this, REDIS_KEY_HASH_JOB, jobId)
			.then(Json.parse);
	}

	inline public function setJob(jobId :JobId, job :DockerBatchComputeJob) :Promise<Bool>
	{
		return RedisPromises.hset(this, REDIS_KEY_HASH_JOB, jobId, Json.stringify(job))
			.thenTrue();
	}

	inline public function removeJob(jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.hdel(this, REDIS_KEY_HASH_JOB, jobId)
			.pipe(function(_) {
				return RedisPromises.hdel(this, REDIS_KEY_HASH_JOB_PARAMETERS, jobId);
			})
			.pipe(function(_) {
				return removeJobWorker(jobId);
			})
			.thenTrue();
	}

	inline public function getJobParameters(jobId :JobId) :Promise<JobParams>
	{
		return RedisPromises.hget(this, REDIS_KEY_HASH_JOB_PARAMETERS, jobId)
			.then(Json.parse);
	}

	inline public function setJobParameters(jobId :JobId, parameters :JobParams) :Promise<Bool>
	{
		return RedisPromises.hset(this, REDIS_KEY_HASH_JOB_PARAMETERS, jobId, Json.stringify(parameters))
			.thenTrue();
	}

	inline public function setJobWorker(jobId :JobId, workerId :MachineId) :Promise<Bool>
	{
		return RedisPromises.hset(this, REDIS_KEY_HASH_JOB_WORKER, jobId, workerId)
			.pipe(function(_) {
				return RedisPromises.sadd(this, REDIS_KEY_SET_PREFIX_WORKER_JOBS + workerId, [jobId]);
			})
			.thenTrue();
	}

	inline public function getJobsOnWorker(workerId :MachineId) :Promise<Array<JobId>>
	{
		return cast RedisPromises.smembers(this, REDIS_KEY_SET_PREFIX_WORKER_JOBS + workerId);
	}

	inline public function getAllWorkerJobs() :Promise<TypedDynamicObject<MachineId, Array<JobId>>>
	{
		return RedisPromises.hgetall(this, REDIS_KEY_HASH_JOB_WORKER)
			.then(function(allKeysAndValues :TypedDynamicObject<JobId, MachineId>) {
				var jobIds = allKeysAndValues.keys();
				var result :TypedDynamicObject<MachineId, Array<JobId>> = {};
				for (jobId in jobIds) {
					var machineId :MachineId = allKeysAndValues.get(jobId);
					if (!result.exists(machineId)) {
						result.set(machineId, []);
					}
					result.get(machineId).push(jobId);
				}
				return result;
			});
	}

	inline public function removeJobWorker(jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.hget(this, REDIS_KEY_HASH_JOB_WORKER, jobId)
			.pipe(function(workerId) {
				if (workerId != null) {
					return RedisPromises.srem(this, REDIS_KEY_SET_PREFIX_WORKER_JOBS + workerId, jobId)
						.pipe(function(_) {
							return return RedisPromises.hdel(this, REDIS_KEY_HASH_JOB_WORKER, jobId);
						})
						.thenTrue();
				} else {
					return Promise.promise(true);
				}
			});
	}

	// inline public function setJobQueueId(jobId :JobId, queueId :String) :Promise<Bool>
	// {
	// 	return RedisPromises.hset(this, REDIS_KEY_HASH_JOB__QUEUE_ID, jobId, queueId)
	// 		.pipe(function() {
	// 			return RedisPromises.hset(this, REDIS_KEY_HASH_QUEUE_ID__JOB, queueId, jobId);
	// 		})
	// 		.thenTrue();
	// }

	// inline public function getQueueId(jobId :JobId) :Promise<String>
	// {
	// 	return RedisPromises.hget(this, REDIS_KEY_HASH_JOB__QUEUE_ID, jobId);
	// }

	// inline public function getJobIdFromQueueId(queueId :String) :Promise<JobId>
	// {
	// 	return RedisPromises.hget(this, REDIS_KEY_HASH_QUEUE_ID__JOB, queueId);
	// }

}

