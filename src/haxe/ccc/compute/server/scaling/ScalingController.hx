package ccc.compute.server.scaling;

import util.DateFormatTools;

/**
 * Individual instances are responsible for themselves shutting down.
 */
class ScalingController
{
	public static function init(injector :Injector)
	{
		if (Sys.environment().get('DEV') == 'true') {
			traceGreen('${ENV_SCALE_UP_CONTROL}=${Sys.environment().get(ENV_SCALE_UP_CONTROL)}');
		}
		Log.debug({SCALE_UP_CONTROL:Sys.environment().get(ENV_SCALE_UP_CONTROL)});
		if (Sys.environment().get(ENV_SCALE_UP_CONTROL) == 'internal') {
			//Switch between AWS and docker here, for now, just use docker
			if (!injector.hasMapping(ICloudProvider)) {
				var scalingProvider :ICloudProvider = new ccc.compute.server.scaling.docker.CloudProviderDocker();
				injector.injectInto(scalingProvider);
				injector.map(ICloudProvider).toValue(scalingProvider);
			}

			var scalingController = new ScalingController();
			injector.injectInto(scalingController);
			injector.map(ScalingController).toValue(scalingController);
		}
	}

	@inject public var _injector :Injector;
	@inject public var _redis :RedisClient;
	@inject public var _cloudProvider :ICloudProvider;
	@inject public var _processQueue :ProcessQueue;
	@inject public var log :AbstractLogger;

	var _globalScalingTimer :RedisDistributedSetInterval;
	var _singletonScalingCall :Promise<Bool>;

	public function new(){}

	@post
	public function postInject()
	{
		log = log.child({c:Type.getClassName(Type.getClass(this)).split('.').pop()});
		getProviderConfig()
			.then(function(providerConfig) {
				var scaleUpTimerInterval :Milliseconds =
				if (providerConfig.scaleUpCheckInterval != null) {
					DateFormatTools.getMsFromString(providerConfig.scaleUpCheckInterval);
				} else {
					new Milliseconds(60 * 1000);//1 minutes
				}

				log.info('Checking scaling every ${scaleUpTimerInterval.toSeconds().toString()}');
				_globalScalingTimer = new RedisDistributedSetInterval(
					DistributedTaskType.RunScaling, scaleUpTimerInterval.toInt(), scalingCheck);
				_injector.injectInto(_globalScalingTimer);
			});
	}

	function getProviderConfig() :Promise<ServiceConfigurationWorkerProvider>
	{
		return ServerConfigTools.getProviderConfig(_injector);
	}

	function getWorkerCreationDuration() :Promise<Milliseconds>
	{
		return getProviderConfig()
			.then(function(config) {
				var workerDuration :Milliseconds =
				if (config.workerCreationDuration != null) {
					DateFormatTools.getMsFromString(config.workerCreationDuration);
				} else {
					new Milliseconds(60 * 3000);//3 minutes
				}
				return workerDuration;
			});
	}

	function scalingCheck() :Void
	{
		if (_singletonScalingCall == null) {
			_singletonScalingCall = scalingCheckInternal()
				.errorPipe(function(err) {
					log.error({error:err, f:'scalingCheck'});
					return Promise.promise(true);
				})
				.then(function(_) {
					_singletonScalingCall = null;
					return true;
				});
		}
	}

	function scalingCheckInternal() :Promise<Bool>
	{
		var jobStateTools :JobStateTools = _redis;
		var Workers :WorkerCache = _redis;
		return jobStateTools.getJobsWithStatus(JobStatus.Pending)
			.pipe(function(pendingJobs) {
				log.debug({log:'scalingCheckInternal', pendingJobsCount:pendingJobs.length});
				return ServerConfigTools.getProviderConfig(_injector)
					.pipe(function(config) {
						return Workers.getAllWorkers()
							.pipe(function(workers) {
								return getWorkerCreationDuration()
									.pipe(function(workerDuration) {
										if (pendingJobs.length > 0 && workers.length < config.maxWorkers) {
											_globalScalingTimer.bump(workerDuration.toFloat());
											log.info('CREATING WORKER, waiting ${workerDuration.toSeconds().toString()} before checking again');
											return _cloudProvider.createWorker();
										} else {
											return Promise.promise(true);
										}
									});
							});
					});
			});
	}
}