package ccc.compute.server.scaling;

abstract WorkerCache(RedisClient) from RedisClient
{
	inline static var PREFIX = '${CCC_PREFIX}workers${SEP}';
	inline static var REDIS_KEY_SET_WORKERS = '${PREFIX}workers';//<MachineId>
	inline static var REDIS_KEY_HASH_WORKER_IP_PRIVATE = '${PREFIX}worker_ip_private';//<MachineId, String>


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
}

