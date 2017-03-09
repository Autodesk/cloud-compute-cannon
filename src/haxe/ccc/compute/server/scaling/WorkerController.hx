package ccc.compute.server.scaling;

typedef WorkerStatus = {

}

/**
 * Individual instances are responsible for themselves shutting down.
 */
class WorkerController
{
	public static function createCloudProvider(injector :Injector) :Promise<Bool>
	{
		return ServerConfigTools.getProviderConfig(injector)
			.then(function(config) {
				var providerType :ServiceWorkerProviderType = config.type;

				var scalingProvider :ICloudProvider = null;
				switch(providerType) {
					case boot2docker:
						scalingProvider = new ccc.compute.server.scaling.docker.CloudProviderDocker();
					case pkgcloud:
						scalingProvider = new ccc.compute.server.scaling.aws.CloudProviderAws();
					default:
						throw 'Unhandled provider type=$providerType';
				}
				injector.injectInto(scalingProvider);
				injector.map(ICloudProvider).toValue(scalingProvider);
				return true;
			});
	}

	public static function init(injector :Injector) :Promise<Bool>
	{
		return createCloudProvider(injector)
			.pipe(function(_) {
				var controller = new WorkerController();
				injector.injectInto(controller);
				injector.map(WorkerController).toValue(controller);
				return controller.ready;
			});
	}

	@inject public var _redis :RedisClient;
	@inject public var _cloudProvider :ICloudProvider;
	@inject public var _docker :Docker;
	@inject public var _injector :Injector;
	@inject public var _internalState :WorkerStateInternal;
	@inject public var log :AbstractLogger;

	public var id (default, null) :MachineId;
	public var hostPrivate (default, null) :String;
	public var ready (default, null) :Promise<Bool>;

	var _globalHealthCheckTimer :RedisDistributedSetInterval;

	public function new() {}

	@post
	public function postInject()
	{
		log = log.child({c:Type.getClassName(Type.getClass(this)).split('.').pop()});
		this.ready = register();
	}

	public function jobCount() :Promise<Int>
	{
		if (id == null) {
			return Promise.promise(0);
		} else {
			var jobTools :Jobs = _redis;
			return jobTools.getJobsOnWorker(id)
				.then(function(jobList) {
					return jobList.length;
				});
		}
	}

	public function updateWorkerStatus() :Promise<WorkerStatus>
	{
		return Promise.promise(null);
	}

	public function unregister() :Promise<Bool>
	{
		var WorkerCache :WorkerCache = _redis;
		return WorkerCache.unregister(id);
	}

	function registerHealthStatus() :Promise<Bool>
	{
		return _cloudProvider.getDiskUsage()
			.pipe(function(usage :Float) {
				var ok = usage < 0.9;
				var workerCache :WorkerCache = _redis;
				if (ok) {
					return setHealthStatus(WorkerHealthStatus.OK);
				} else {
					log.error({message: 'Failed health check', status:WorkerHealthStatus.BAD_DiskFull});
					return setHealthStatus(WorkerHealthStatus.BAD_DiskFull);
				}
			})
			.errorPipe(function(err) {
				log.error({error:err, message: 'Failed health check'});
				var workerCache :WorkerCache = _redis;
				return setHealthStatus(WorkerHealthStatus.BAD_Unknown)
					.thenTrue()
					.errorPipe(function(err) {
						log.error({error:err, f:'registerHealthStatus'});
						return Promise.promise(true);
					});
			});
	}

	function setHealthStatus(status :WorkerHealthStatus) :Promise<Bool>
	{
		if (Sys.getEnv('LOCAL') != "true") {
			log.debug({healthstatus:status});
		}
		var workerCache :WorkerCache = _redis;
		return workerCache.setHealthStatus(id, status);
	}

	function register() :Promise<Bool>
	{
		var WorkerCache :WorkerCache = _redis;
		return _cloudProvider.getId()
			.pipe(function(machineId) {
				Assert.notNull(machineId);
				this.id = machineId;
				_internalState.id = machineId;
				// _injector.map(String, WORKER_ID).toValue(this.id);
				log = log.child({id:this.id});
				return registerHealthStatus()
					.pipe(function(_) {
						return WorkerCache.register(machineId);
					});
			})
			.pipe(function(_) {
				return _cloudProvider.getHostPrivate()
					.pipe(function(host) {
						if (host != null) {
							this.hostPrivate = host;
							return WorkerCache.setPrivateHost(this.id, host);
						} else {
							return Promise.promise(true);
						}
					});
			})
			.then(function(_) {
				//Register the health of this instance.
				//AWS lambdas will use this value
				Node.setInterval(function() {
					registerHealthStatus();
				}, WORKER_STATUS_CHECK_INTERVAL_SECONDS * 1000);
				return true;
			})
			.then(function(_) {
				_globalHealthCheckTimer = new RedisDistributedSetInterval(
					DistributedTaskType.CheckAllWorkerHealth,
					GLOBAL_WORKER_HEALTH_CHECK_SECONDS * 1000,
					checkOtherMachines);
				_injector.injectInto(_globalHealthCheckTimer);
				return true;
			})
			.thenTrue();
	}

	function checkOtherMachines()
	{
		var Jobs :Jobs = _redis;
		return Jobs.checkIfWorkersFailedIfSoRemoveJobs();
	}
}