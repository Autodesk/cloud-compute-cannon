package ccc.compute.shared;

import ccc.compute.shared.provider.CloudProviderType;

@:build(util.NodejsMacros.addProcessEnvVars())
class ServerConfig
{
	@NodeProcessVar
	public static var CLOUD_PROVIDER_TYPE :CloudProviderType = 'local';

	@NodeProcessVar
	public static var DISABLE_STARTUP_TESTS :Bool = true;


	/**
	 * If true, disables all queue processing logic
	 * (i.e. no jobs will be run on this process)
	 * Jobs can still be added.
	 * This allows separating the servers fronting
	 * requests from the servers processing jobs.
	 * This allows a higher degree of security since
	 * the servers fronting requests then do not need
	 * to mount the docker host.
	 */
	@NodeProcessVar
	public static var DISABLE_WORKER :Bool = false;

	@NodeProcessVar
	public static var FLUENT_HOST :String;

	@NodeProcessVar
	public static var FLUENT_PORT :Int = 24225;

	@NodeProcessVar
	public static var HOST :String = 'http://ccc.local';

	@NodeProcessVar
	public static var LOADER_IO_TOKEN :String;

	@NodeProcessVar
	public static var LOG_LEVEL :String = 'info';

	@NodeProcessVar
	public static var LOGGING_DISABLE :Bool = false;

	@NodeProcessVar
	public static var JOB_MAX_ATTEMPTS :Int = 5;

	@NodeProcessVar
	public static var JOB_TURBO_MAX_TIME_SECONDS :Int = 300;

	/**
	 * If a job has completed successfully in the last interval
	 * below, then monitor checks can use that job as evidence
	 * that the system is healthy rather than starting a new job.
	 * Defaults to three minutes.
	 */
	@NodeProcessVar
	public static var MONITOR_DEFAULT_JOB_COMPLETED_WITHIN_SECONDS :Int = 180;

	/**
	 * Monitor requests will always return within this time
	 */
	@NodeProcessVar
	public static var MONITOR_TIMEOUT_SECONDS :Int = 30;

	@NodeProcessVar
	public static var PORT :Int = 9000;

	@NodeProcessVar
	public static var REDIS_HOST :String = 'redis';

	@NodeProcessVar
	public static var REDIS_PORT :Int = 6379;

	@NodeProcessVar
	public static var STORAGE_HTTP_PREFIX :String = 'http://ccc.local';

	@NodeProcessVar
	public static var TRAVIS :Bool = false;

	/**
	 * The interval where workers report their health status to redis
	 */
	@NodeProcessVar
	public static var WORKER_STATUS_CHECK_INTERVAL_SECONDS :Int = 20;

	//Statics
	inline public static var INJECTOR_REDIS_SUBSCRIBE :String = 'REDIS_SUBSCRIBE';
	inline public static var REDIS_PREFIX :String = 'ccc::';

	public static function toJson() :Dynamic
	{
		return {
			'CLOUD_PROVIDER_TYPE': CLOUD_PROVIDER_TYPE,
			'DISABLE_STARTUP_TESTS': DISABLE_STARTUP_TESTS,
			'FLUENT_HOST': FLUENT_HOST,
			'FLUENT_PORT': FLUENT_PORT,
			'HOST': HOST,
			'LOG_LEVEL': LOG_LEVEL,
			'PORT': PORT,
			'REDIS_HOST': REDIS_HOST,
			'REDIS_PORT': REDIS_PORT,
			'STORAGE_HTTP_PREFIX': STORAGE_HTTP_PREFIX,
			'TRAVIS': TRAVIS,
			'WORKER_STATUS_CHECK_INTERVAL_SECONDS': WORKER_STATUS_CHECK_INTERVAL_SECONDS,
		};
	}
}