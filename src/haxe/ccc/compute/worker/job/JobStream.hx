package ccc.compute.worker.job;

class JobStream
{
	public static function getStatusStream() :Stream<JobStatsData>
	{
		var StatusStream :Stream<JobStatsData> =
			RedisTools.createStreamCustom(
				REDIS_CLIENT,
				JobStatsTools.REDIS_CHANNEL_STATUS,
				function(jobId :JobId) {
					// traceYellow('Channel "${JobStatsTools.REDIS_CHANNEL_STATUS}" value=${jobId}');
					return JobStatsTools.get(jobId)
						.then(function(r) {
							// traceYellow('Channel "${JobStatsTools.REDIS_CHANNEL_STATUS}" value=${jobId} result=${Json.stringify(r)}');
							return r;
						});
				});
		StatusStream.catchError(function(err) {
			Log.error({error:err, message: 'Failure on '});
		});
		return StatusStream;
	}

	public static function getActiveJobStream() :Stream<Array<JobId>>
	{
		var ActiveJobsStream :Stream<Array<JobId>> =
			RedisTools.createStreamCustom(
				REDIS_CLIENT,
				JobStatsTools.REDIS_CHANNEL_JOBS_ACTIVE,
				function(jobIdsString :String) {
					return Promise.promise(Json.parse(jobIdsString));
				});
		ActiveJobsStream.catchError(function(err) {
			Log.error({error:err, message: 'Failure on getActiveJobStream'});
		});
		return ActiveJobsStream;
	}

	public static function getFinishedJobStream() :Stream<Array<JobId>>
	{
		var finishedJobsStream :Stream<Array<JobId>> =
			RedisTools.createStreamCustom(
				REDIS_CLIENT,
				JobStatsTools.REDIS_CHANNEL_JOBS_FINISHED,
				function(jobIdsString :String) {
					return Promise.promise(Json.parse(jobIdsString));
				});
		finishedJobsStream.catchError(function(err) {
			Log.error({error:err, message: 'Failure on getFinishedJobStream'});
		});
		return finishedJobsStream;
	}
	public static function init(redis :RedisClient) :Promise<Bool>
	{
		REDIS_CLIENT = redis;
		return Promise.promise(true);
	}

	static var REDIS_CLIENT :RedisClient;
}