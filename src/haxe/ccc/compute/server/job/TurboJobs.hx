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

	inline public function startJob(jobId :JobId, ttl :Int) :Promise<Bool>
	{
		return RedisPromises.setex(this, '${CCC_PREFIX}turbojob${SEP}$jobId${SEP}$ttl', ttl, jobId)
			.thenTrue();
	}
}