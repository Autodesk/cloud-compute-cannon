package ccc.compute.shared;

/**
 * Parse env vars from the process.
 * All variables annotated with "@NodeProcessVar"
 * are pulled from the process.env (environment
 * variables). The macro that processes those can
 * parse Bool/Int/Float types from the string, so
 * we directly used the typed variable.
 */

import ccc.compute.shared.provider.CloudProviderType;

@:build(util.NodejsMacros.addProcessEnvVars())
class ServerConfig
{
	/**
	 * TODO: this might not be necessary.
	 * When running the API server as a single GPU
	 * node, set this to 1 or true. This disables
	 * a lot of code paths involved in remote caches
	 * remote storage, etc.
	 */
	@NodeProcessVar
	public static var SINGLE_NODE :Bool = false;

	/**
	 * Currently supported values:
	 *  - local (default, a local stack running in docker-compose)
	 *  - aws (Amazon Web Services)
	 */
	@NodeProcessVar
	public static var CLOUD_PROVIDER_TYPE :CloudProviderType = 'local';

	/**
	 * S3 credentials
	 */

	@NodeProcessVar
	public static var AWS_S3_KEYID :String;

	@NodeProcessVar
	public static var AWS_S3_KEY :String;

	@NodeProcessVar
	public static var AWS_S3_BUCKET :String;

	@NodeProcessVar
	public static var AWS_S3_REGION :String;

	@NodeProcessVar
	public static var STORAGE_PATH_BASE :String = "/jobs";

	/**
	 * If true, disables all queue processing logic
	 * (i.e. no jobs will be run on this process)
	 * Jobs can still be added.
	 * This allows separating the servers fronting
	 * requests from the servers processing jobs.
	 * This allows a higher degree of security since
	 * the servers fronting requests then do not need
	 * to mount the docker host.
	 * Also worker instances can be GPU enabled,
	 * while the front-end servers do not have to.
	 */
	@NodeProcessVar
	public static var DISABLE_WORKER :Bool = false;

	/**
	 * The host for the fluent log aggregator. If this
	 * is not set, fluent logs will not be sent
	 */
	@NodeProcessVar
	public static var FLUENT_HOST :String;

	@NodeProcessVar
	public static var FLUENT_PORT :Int = 24225;

	/**
	 * Used only when CLOUD_PROVIDER_TYPE=local
	 * The default allows the nginx reverse proxy
	 * to automatically route requests to ccc
	 * servers for newly created ccc containers.
	 */
	@NodeProcessVar
	public static var HOST :String = 'http://ccc.local';

	/**
	 * If the kibana url is passed in to the app, it
	 * can then be shown in the dashboard, so you don't
	 * have to remember. In the future, we can show a
	 * dashboard in an iframe.
	 */
	@NodeProcessVar
	public static var KIBANA_URL :String = 'http://localhost:5601';

	/**
	 * Bunyan log level (trace|debug|info|warn|error|critical)
	 */
	@NodeProcessVar
	public static var LOG_LEVEL :String = 'info';

	/**
	 * If you want to completely disable all logging.
	 */
	@NodeProcessVar
	public static var LOGGING_DISABLE :Bool = false;

	/**
	 * The maximum number of times a job will be retried
	 * after failures before giving up. NB: if a job returns
	 * a non-zero exit code, this can still be considered
	 * a successful job. The kinds of job failures that
	 * trigger this specified restart are system failures.
	 */
	@NodeProcessVar
	public static var JOB_MAX_ATTEMPTS :Int = 5;

	/**
	 * The default maximum time allowed for a turbo job
	 * (excluded time needed for downloading the docker
	 * image on the worker).
	 */
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

	/**
	 * The server process listen port. You won't ever need to change this.
	 */
	@NodeProcessVar
	public static var PORT :Int = 9000;

	@NodeProcessVar
	public static var REDIS_HOST :String = 'redis';

	@NodeProcessVar
	public static var REDIS_PORT :Int = 6379;

	/**
	 * This needs to be better documented. Local development only.
	 */
	@NodeProcessVar
	public static var STORAGE_HTTP_PREFIX :String = 'http://ccc.local';

	/**
	 * The interval where workers report their health status to redis
	 */
	@NodeProcessVar
	public static var WORKER_STATUS_CHECK_INTERVAL_SECONDS :Int = 20;

	//Statics. You don't need to change these unless you're developing.
	inline public static var INJECTOR_REDIS_SUBSCRIBE :String = 'REDIS_SUBSCRIBE';
	inline public static var REDIS_PREFIX :String = 'ccc::';

	public static function toJson() :Dynamic
	{
		return {
			'CLOUD_PROVIDER_TYPE': CLOUD_PROVIDER_TYPE,
			'DISABLE_WORKER': DISABLE_WORKER,
			'FLUENT_HOST': FLUENT_HOST,
			'FLUENT_PORT': FLUENT_PORT,
			'HOST': HOST,
			'JOB_MAX_ATTEMPTS': JOB_MAX_ATTEMPTS,
			'JOB_TURBO_MAX_TIME_SECONDS': JOB_TURBO_MAX_TIME_SECONDS,
			'LOG_LEVEL': LOG_LEVEL,
			'PORT': PORT,
			'STORAGE_HTTP_PREFIX': STORAGE_HTTP_PREFIX,
			'WORKER_STATUS_CHECK_INTERVAL_SECONDS': WORKER_STATUS_CHECK_INTERVAL_SECONDS,
		};
	}
}