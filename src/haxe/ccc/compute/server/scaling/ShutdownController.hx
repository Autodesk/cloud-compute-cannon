package ccc.compute.server.scaling;

// import promhx.RequestPromises;

/**
 * Individual instances are responsible for themselves shutting down.
 */
class ShutdownController
{
	public static function init(injector :Injector)
	{
		if (Sys.environment().get(ENV_SCALE_DOWN_CONTROL) == 'internal') {
			var shutdownController = new ShutdownController();
			injector.map(ShutdownController).toValue(shutdownController);
			injector.injectInto(shutdownController);
		}
	}

	public function new() {}

	@inject public var _injector :Injector;
	@inject public var _redis :RedisClient;
	@inject public var _cloudProvider :ICloudProvider;
	@inject public var _workerController :WorkerController;
	@inject public var _processQueue :ProcessQueue;
	@inject public var log :AbstractLogger;
	var _monitorSelfTimerId :Dynamic;
	var _monitorWorkersTask :RedisDistributedSetInterval;
	var _disposed :Bool = false;

	@post
	public function postInject()
	{
		log = log.child({c:Type.getClassName(Type.getClass(this)).split('.').pop()});

		if (Sys.environment().get(ENV_SCALE_DOWN_CONTROL) == 'internal') {
			beginShutdownMonitor();
		}

		// _monitorWorkersTask = new RedisDistributedSetInterval(
		// 	DistributedTaskType.CheckAllWorkerHealth,
		// 	10000,
		// 	// 5000,
		// 	checkOtherMachines);

		// _injector.injectInto(_monitorWorkersTask);
	}

	function beginShutdownMonitor() :Void
	{
		//Don't begin this right away, let it have some time first
		Node.setTimeout(function() {
			if (!_disposed) {
				_monitorSelfTimerId = Node.setInterval(selfShutdownCheck, 5000);
			}
		}, 10000);
	}

	function selfShutdownCheck() :Void
	{
		traceCyan('selfShutdownCheck');
		_cloudProvider.getBestShutdownTime()
			.then(function(shutdownTime) {
				traceCyan('selfShutdownCheck _processQueue.jobs=${_processQueue.jobs} shutdownTime=' + Date.fromTime(shutdownTime).toString());
				var now = Date.now().getTime();
				if (now >= shutdownTime && _processQueue.isQueueEmpty())  {
					//Wait a bit before checking again to shut down
					Node.setTimeout(function() {
						_processQueue.stopQueue()
							.pipe(function(_) {
								log.warn({m:'Shutting down! ProcessQueue empty!'});
								return _workerController.unregister()
									.pipe(function(_) {
										return _cloudProvider.shutdownThisInstance();
									});
							});
					}, 5000);
				} else {
					traceCyan('selfShutdownCheck no');
				}
			})
			.catchError(function(err) {
				log.error({error:err});
			});
	}

	function checkOtherMachines()
	{
		traceMagenta('checkOtherMachines');
		var workers :WorkerCache = _redis;
		workers.getAllWorkers()
			.then(function(workerIds) {
				traceMagenta('checkOtherMachines workerIds=$workerIds');
				var promises = workerIds.map(function(workerId) {
					return checkWorker(workerId)
						.then(function(ok) {
							if (!ok) {
								removeWorker(workerId);
							}
							return true;
						});
				});
				return Promise.whenAll(promises)
					.thenTrue();
			});
	}

	function checkWorker(machineId :MachineId) :Promise<Bool>
	{
		var workers :WorkerCache = _redis;
		return workers.getPrivateHost(machineId)
			.pipe(function(host) {
				var maxRetries = 3;
				var interval = 2000;
				var url = 'http://${host}:${SERVER_DEFAULT_PORT}/version';
				traceMagenta('Checking $url');
				return RetryPromise.pollRegular(
					function() {
						var promise = new DeferredPromise();
						js.npm.request.Request.get(url, function(err, res, body) {
							if (err != null) {
								promise.boundPromise.reject(err);
							} else {
								if (res.statusCode != 200) {
									promise.boundPromise.reject('statusCode=${res.statusCode}');
								} else {
									promise.resolve(true);
								}
							}
						});
						// return RequestPromises.get(url, 2000);
						return promise.boundPromise;
					},
					maxRetries,
					interval, 'checkWorker')
				.thenTrue()
				.errorPipe(function(err) {
					log.error({error:err, log:'Failed to reach $machineId @ $url'});
					return Promise.promise(false);
				});
			});
	}

	function removeWorker(workerId :MachineId)
	{
		var Workers :WorkerCache = _redis;
		var Jobs :Jobs = _redis;
		return Promise.promise(true)
			.pipe(function(_) {
				return Workers.unregister(workerId);
			})
			.pipe(function(_) {
				return _cloudProvider.terminate(workerId)
					.errorPipe(function(err) {
						log.error({error:err, log:'Failed to remove worker', workerId:workerId});
						return Promise.promise(true);
					});
			})
			.pipe(function(_) {
				return Jobs.getJobsOnWorker(workerId)
					.pipe(function(jobsOnWorker) {
						var promises = jobsOnWorker.map(function(jobId) {
							return Jobs.removeJobWorker(jobId, workerId);
						});
						return Promise.whenAll(promises).thenTrue();
					});
			});
	}

	public function dispose()
	{
		if (_disposed) {
			return;
		}
		_disposed = true;
		Node.clearInterval(_monitorSelfTimerId);
		_monitorWorkersTask.dispose();
		_monitorWorkersTask = null;
	}
}