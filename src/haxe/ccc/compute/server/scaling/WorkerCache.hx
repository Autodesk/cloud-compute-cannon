package ccc.compute.server.scaling;

abstract WorkerCache(RedisClient) from RedisClient
{
	inline static var PREFIX = '${CCC_PREFIX}workers${SEP}';
	inline public static var REDIS_KEY_SET_WORKERS = '${PREFIX}workers';//<MachineId>
	inline public static var REDIS_KEY_HASH_WORKER_IP_PRIVATE = '${PREFIX}worker_ip_private';//<MachineId, String>
	inline public static var REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS = '${PREFIX}worker_health_status${SEP}';//<WorkerHealthStatus>

	inline function new(r :RedisClient)
	{
		this = r;
	}

	inline public function init()
	{
		return Promise.promise(true);
	}

	inline public function register(machineId :MachineId) :Promise<Bool>
	{
		return RedisPromises.sadd(this, REDIS_KEY_SET_WORKERS, [machineId])
			.thenTrue();
	}

	inline public function unregister(machineId :MachineId) :Promise<Bool>
	{
		return RedisPromises.srem(this, REDIS_KEY_SET_WORKERS, machineId)
			.pipe(function(_) {
				return RedisPromises.hdel(this, REDIS_KEY_HASH_WORKER_IP_PRIVATE, machineId);
			})
			.thenTrue();
	}

	inline public function getAllWorkers() :Promise<Array<MachineId>>
	{
		return cast RedisPromises.smembers(this, REDIS_KEY_SET_WORKERS);
	}

	inline public function setPrivateHost(machineId :MachineId, host :String) :Promise<Bool>
	{
		return RedisPromises.hset(this, REDIS_KEY_HASH_WORKER_IP_PRIVATE, machineId, host)
			.thenTrue();
	}

	inline public function getPrivateHost(machineId :MachineId) :Promise<String>
	{
		return RedisPromises.hget(this, REDIS_KEY_HASH_WORKER_IP_PRIVATE, machineId);
	}

	inline public function setHealthStatus(machineId :MachineId, status :WorkerHealthStatus) :Promise<Bool>
	{
		var key = '${REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}${machineId}';
		return RedisPromises.setex(this, key, WORKER_STATUS_KEY_TTL_SECONDS, status)
			.thenTrue();
	}

	inline public function getHealthStatus(machineId :MachineId) :Promise<WorkerHealthStatus>
	{
		var key = '${REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}${machineId}';
		return RedisPromises.get(this, key)
			.then(function(s :String) {
				var status :WorkerHealthStatus = s;
				if (s == null) {
					status = WorkerHealthStatus.NULL;
				}
				return status;
			});
	}

	inline public function getWorkerHealthStatuses(machineId :MachineId, status :WorkerHealthStatus) :Promise<TypedDynamicObject<MachineId, WorkerHealthStatus>>
	{
		var redis :RedisClient = this;
		return RedisPromises.keys(redis, '${REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}*')
			.pipe(function(workers :Array<MachineId>) {
				var result :TypedDynamicObject<MachineId, WorkerHealthStatus> = {};
				var promises :Array<Promise<Bool>> = workers.map(function(instanceHealthKey) {
					return RedisPromises.get(redis, instanceHealthKey)
						.then(function(val) {
							result.set(instanceHealthKey.replace(REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS, ''), val);
							return true;
						});
				});
				return Promise.whenAll(promises)
					.then(function(_) {
						return result;
					});
			});
	}
}

