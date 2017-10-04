package ccc.compute.worker;

class WorkerStreams
{
	public static function createWorkerStatusStream(redis :RedisClient)
	{
		var workerChangedStream :Stream<WorkerState> =
			RedisTools.createStreamCustom(
				redis,
				WorkerStateRedis.REDIS_MACHINE_UPDATED_CHANNEL,
				function(id :MachineId) {
					if (id != null) {
						return WorkerStateRedis.get(id);
					} else {
						return Promise.promise(null);
					}
				}
			);
		workerChangedStream.catchError(function(err) {
			Log.error({error:err, message: 'Failure on workerChangedStream'});
		});
		return workerChangedStream;
	}

	public static function until(redis :RedisClient, machineId :MachineId, predicate :WorkerState->Bool, timeout :Int)
	{
		var promise = new DeferredPromise();
		var stream = createWorkerStatusStream(redis);
		var thenStream;
		var timeoutId :Dynamic;

		var cleanup = function() {
			if (thenStream != null) {
				thenStream.end();
				stream.end();
				thenStream = null;
				stream = null;
			}
			promise = null;
			if (timeoutId != null) {
				Node.clearTimeout(timeoutId);
				timeoutId = null;
			}
		};

		stream.then(function(blob) {
			if (blob != null && promise != null) {
				if (predicate(blob)) {
					promise.resolve(true);
					cleanup();
				}
			}
		});

		timeoutId = Node.setTimeout(function() {
			if (promise != null) {
				promise.boundPromise.reject('TimedOut');
			}
			cleanup();
		}, timeout);

		WorkerStateRedis.get(machineId)
			.then(function(blob) {
				if (promise != null && blob != null && predicate(blob)) {
					promise.resolve(true);
					cleanup();
				}
			})
			.catchError(function(err) {
				traceRed(err);
			});

		return promise.boundPromise;
	}
}