package ccc.compute.server.job;

import js.npm.RedisClient;
import js.npm.redis.RedisLuaTools;

abstract TurboJobs(RedisClient) from RedisClient
{
	inline function new(r :RedisClient)
	{
		this = r;
	}

	inline public function init()
	{
		return Promise.promise(true);
	}

	inline public function jobStart(jobId :JobId, ttl :Int, instance :MachineId) :Promise<Bool>
	{
		return RedisPromises.setex(this, '${CCC_PREFIX}turbojob${SEP}$jobId${SEP}${instance}${SEP}$ttl', ttl, jobId)
			.thenTrue();
	}

	inline public function jobEnd(jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.keys(this, '${CCC_PREFIX}turbojob${SEP}$jobId${SEP}*')
			.pipe(function(keys) {
				if (keys != null && keys.length > 0) {
					return RedisPromises.del(this, keys[0])
						.thenTrue();
				} else {
					return Promise.promise(true);
				}
			});
	}

	inline public function isJob(jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.keys(this, '${CCC_PREFIX}turbojob${SEP}$jobId${SEP}*')
			.then(function(keys) {
				return keys != null && keys.length > 0;
			});
	}
}