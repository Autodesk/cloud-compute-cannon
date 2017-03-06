package ccc.compute.server.scaling;

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
	@inject public var log :AbstractLogger;

	public var id (default, null) :MachineId;
	public var hostPrivate (default, null) :String;
	public var ready (default, null) :Promise<Bool>;

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

	public function unregister() :Promise<Bool>
	{
		var WorkerCache :WorkerCache = _redis;
		return WorkerCache.unregister(id);
	}

	function register() :Promise<Bool>
	{
		var WorkerCache :WorkerCache = _redis;
		return _cloudProvider.getId()
			.pipe(function(machineId) {
				Assert.notNull(machineId);
				this.id = machineId;
				return WorkerCache.register(machineId);
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
			.thenTrue();
	}
}