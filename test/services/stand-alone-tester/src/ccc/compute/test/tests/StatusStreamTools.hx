package ccc.compute.test.tests;

class StatusStreamTools
{
	public static function waitUntilJobIsRunningInContainer(stream :Stream<JobStatsData>, jobId :JobId, attempt :Int, ?endStream :Bool = true) :Promise<DockerContainerId>
	{
		var promise = new promhx.deferred.DeferredPromise();
		var streamLocal;
		var end = function() {
			promise = null;
			streamLocal.end();
			if (endStream) {
				stream.end();
			}
		}
		streamLocal = stream.then(function(jobStats) {
			if (promise != null && jobStats.jobId == jobId && jobStats.attempts[attempt - 1] != null && jobStats.attempts[attempt - 1].statusWorking == JobWorkingStatus.ContainerRunning) {
				JobStatsTools.getJobContainer(jobId, attempt)
					.then(function(containerid) {
						if (promise != null) {
							promise.resolve(containerid);
						}
						end();
					})
					.errorThen(function(err) {
						Log.warn({error:err, message:'Error in getting job container'});
						if (promise != null) {
							promise.boundPromise.reject(err);
						}
					});
			} else {
				if (promise != null && jobStats.jobId == jobId && jobStats.status == JobStatus.Finished) {
					promise.boundPromise.reject('Already finished');
					end();
				}
			}
		});

		return promise.boundPromise;
	}

	public static function waitUntilJobIsOnAttemptNumber(stream :Stream<JobStatsData>, jobId :JobId, attempt :Int, ?endStream :Bool = true) :Promise<Bool>
	{
		var promise = new promhx.deferred.DeferredPromise();
		var streamLocal;
		var end = function() {
			promise = null;
			streamLocal.end();
			if (endStream) {
				stream.end();
			}
		}
		streamLocal = stream.then(function(jobStats) {
			if (promise != null && jobStats.jobId == jobId) {
				if (jobStats.attempts.length >= attempt) {
					promise.resolve(true);
					end();
				}
			} else {
				if (promise != null && jobStats.jobId == jobId && jobStats.status == JobStatus.Finished) {
					promise.boundPromise.reject('Already finished');
					end();
				}
			}
		});

		return promise.boundPromise;
	}

	public static function waitUntilJobIsFinished(stream :Stream<JobStatsData>, jobId :JobId, ?endStream :Bool = true) :Promise<Bool>
	{
		var promise = new promhx.deferred.DeferredPromise();
		var streamLocal;
		var end = function() {
			promise = null;
			streamLocal.end();
			if (endStream) {
				stream.end();
			}
		}
		streamLocal = stream.then(function(jobStats) {
			if (promise != null && jobStats.jobId == jobId && jobStats.status == JobStatus.Finished) {
				promise.resolve(true);
				end();
			}
		});

		return promise.boundPromise;
	}
}

