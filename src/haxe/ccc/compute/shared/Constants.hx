package ccc.compute.shared;

import ccc.SharedConstants.*;

import haxe.Json;
import t9.abstracts.net.*;

using StringTools;

/**
 *********************************************
 * General DEFINITIONS
 **********************************************
 */

class Constants
{
	/* Networking */
	public static var SERVER_HOSTNAME_PRIVATE :String;
	public static var SERVER_HOSTNAME_PUBLIC :String;

	/* General */
	inline public static var BUILD_DIR_SERVER = 'build/server';
	inline public static var APP_NAME = 'cloud-compute-cannon';
	public static var APP_SERVER_FILE = APP_NAME + '-server.js';
	public static var APP_NAME_COMPACT = APP_NAME.replace('-', '');
	public static var DOCKER_COMPOSE_SERVICE = 'ccc';
	public static var CLI_COMMAND = APP_NAME_COMPACT;

	/* Redis */
	inline public static var JOB_ID_ATTEMPT_SEP = '_';
	inline public static var CONFIG_HASH = 'ccc_config';
	inline public static var CONFIG_HASH_WORKERS_MAX = 'workers_max';
	inline public static var CONFIG_HASH_WORKERS_MIN = 'workers_min';
	inline public static var WORKER_STATUS_KEY_TTL_SECONDS = 20;
	// inline public static var WORKER_STATUS_CHECK_INTERVAL_SECONDS = 10;
	inline public static var GLOBAL_WORKER_HEALTH_CHECK_SECONDS = 20;

	/* Job constants */
	public static inline var RESULTS_JSON_FILE = 'result.json';
	public static inline var DIRECTORY_INPUTS = 'inputs';
	public static inline var DIRECTORY_OUTPUTS = 'outputs';
	public static var LOCAL_WORKER_HOST_MOUNT_PREFIX = '';
	public static inline var DIRECTORY_NAME_WORKER_OUTPUT = 'computejobs';
	/** If you change this, change etc/log/plugins/output_worker_log.rb */
	inline public static var WORKER_JOB_DATA_DIRECTORY_WITHIN_CONTAINER = '/$DIRECTORY_NAME_WORKER_OUTPUT/';
	// public static var DIRECTORY_WORKER_BASE = '/tmp/$DIRECTORY_NAME_WORKER_OUTPUT/';
	public static var WORKER_JOB_DATA_DIRECTORY_HOST_MOUNT = '/$DIRECTORY_NAME_WORKER_OUTPUT/';
	// public static var SERVER_DATA_ROOT = '/$DIRECTORY_NAME_WORKER_OUTPUT/';
	public static inline var STDOUT_FILE = 'stdout';
	public static inline var STDERR_FILE = 'stderr';
	public static inline var DEFAULT_MAX_JOB_TIME_MS = 30 * 1000;//30secs
	public static inline var TURBO_JOB_MAX_TIME_SECONDS_DEFAULT :Int = 30;

	/* Env vars */
	inline public static var ENV_VAR_DISABLE_LOGGING = 'DISABLE_LOGGING';
	inline public static var ENV_VAR_AWS_PROVIDER_CONFIG = 'AWS_PROVIDER_CONFIG';
	inline public static var ENV_VAR_COMPUTE_CONFIG = 'COMPUTE_CONFIG';
	inline public static var ENV_VAR_COMPUTE_CONFIG_PATH = 'CONFIG_PATH';
	/* Env vars for running tests*/
	inline public static var ENV_AWS_KEY = 'AWS_KEY';
	inline public static var ENV_AWS_KEYID = 'AWS_KEYID';
	inline public static var ENV_AWS_REGION = 'AWS_REGION';
	inline public static var ENV_VAR_CCC_ADDRESS = 'CCC_ADDRESS';
	inline public static var ENV_DISABLE_SERVER_CHECKS = 'DISABLE_SERVER_CHECKS';
	inline public static var ENV_LOG_LEVEL = 'LOG_LEVEL';
	inline public static var ENV_TRAVIS = 'TRAVIS';
	/* A flag ("true") to determine if the CLI installed this server */
	inline public static var ENV_CLIENT_DEPLOYMENT = 'CLIENT_DEPLOYMENT';
	inline public static var ENV_CLEAR_DB_ON_START = 'CLEAR_DB_ON_START';
	inline public static var ENV_DISABLE_STARTUP_TEST = 'DISABLE_STARTUP_TEST';
	inline public static var ENV_REMOVE_JOBS_ON_STARTUP = 'REMOVE_JOBS_ON_STARTUP';
	inline public static var ENV_ENABLE_FLUENT = 'ENABLE_FLUENT';
	/* Injector env vars */
	inline public static var ENV_REDIS_HOST = 'REDIS_HOST';
	inline public static var ENV_REDIS_PORT = 'REDIS_PORT';
	// inline public static var WORKER_ID = 'WORKER_ID';
	// inline public static var NCPUS = 'NCPUS';
	// inline public static var WORKING_JOBS = 'WORKING_JOBS';
	// inline public static var TIME_LAST_HEALTH_CHECK = 'TIME_LAST_HEALTH_CHECK';
	/* Scaling control: values [internal/external] defaults to external */
	inline public static var ENV_SCALE_UP_CONTROL = 'SCALE_UP_CONTROL';
	/* external | internal */
	inline public static var ENV_SCALE_DOWN_CONTROL = 'SCALE_DOWN_CONTROL';


	/* Server */
	public static var DOCKER_CONTAINER_ID :String = null;
	public static var DOCKER_CONTAINER_NAME :String = null;
	inline public static var SERVER_DEFAULT_PORT = 9000;
	public static var SERVER_PUBLIC_HOST = new Host(new HostName('ccc.bionano.autodesk.com'), new Port(SERVER_DEFAULT_PORT));
	inline public static var SERVER_RELOADER_PORT = 9002;
	inline public static var REDIS_PORT = 6379;
	inline public static var DOCKER_PORT = 2375;
	inline public static var DEFAULT_REDIS_PORT = 6379;
	public static var DOCKER_CONNECT_OPTS_LOCAL = {socketPath:'/var/run/docker.sock'};
	inline public static var SERVER_PATH_CHECKS = '/checks';
	inline public static var SERVER_PATH_CHECKS_OK = 'OK';
	inline public static var SERVER_PATH_RELOAD = '/reload';
	inline public static var SERVER_PATH_STATUS = '/status';
	inline public static var SERVER_PATH_READY = '/ready';
	inline public static var SERVER_PATH_WAIT = '/wait';
	inline public static var SERVER_API_URL = '/api';
	inline public static var SERVER_API_RPC_URL_FRAGMENT = '/rpc';
	inline public static var SERVER_RPC_URL = '${SERVER_API_URL}${SERVER_API_RPC_URL_FRAGMENT}';
	inline public static var SERVER_URL_API_DOCKER_IMAGE_BUILD = '$SERVER_API_URL/build';
	inline public static var DOCKER_IMAGE_DEFAULT = 'docker.io/busybox:latest';
	inline public static var SERVER_CONTAINER_TAG_SERVER = 'ccc_server';
	inline public static var SERVER_CONTAINER_TAG_REDIS = 'ccc_redis';
	inline public static var SERVER_INSTALL_COMPOSE_SCRIPT = 'etc/server/install_docker_compose.sh';
	inline public static var SERVER_MOUNTED_CONFIG_FILE_NAME = 'ccc.yml';
	inline public static var SERVER_MOUNTED_CONFIG_FILE_DEFAULT = 'config/$SERVER_MOUNTED_CONFIG_FILE_NAME';
	public static var SERVER_LOCAL_HOST :Host = new Host(new HostName('localhost'), new Port(SERVER_DEFAULT_PORT));

	/* WORKER TAGS */
	inline public static var INSTANCE_TAG_TYPE_KEY = 'CCC_TYPE';
	inline public static var INSTANCE_TAG_TYPE_VALUE_WORKER = 'worker';
	inline public static var INSTANCE_TAG_TYPE_VALUE_SERVER = 'server';
	inline public static var INSTANCE_TAG_OWNER_KEY = 'CCC_OWNER';

	/* Fluent/logging */
	inline public static var FLUENTD_SOURCE_PORT = 24225;
	inline public static var FLUENTD_HTTP_COLLECTOR_PORT = 9881;
	public static var FLUENTD_NODEJS_BUNYAN_TAG_PREFIX = 'docker.nodejs-bunyan';
	public static var FLUENTD_WORKER_LOG_TAG_PREFIX = 'docker.$APP_NAME_COMPACT.worker';
	public static var FLUENTD_SERVER_LOG_TAG_PREFIX = '$FLUENTD_NODEJS_BUNYAN_TAG_PREFIX.$APP_NAME_COMPACT.server';

	/* RPC */
	inline public static var URL_SUBMIT_JOB_MULTIPART = 'submit_job_multipart';
	inline public static var MULTIPART_FILE_KEY_DOCKER_CONTEXT = 'docker_context';

	/* Misc RPC methods not yet through the JsonRpc system */
	inline public static var RPC_METHOD_JOB_NOTIFY = 'batchcompute.jobnotify';
	public static var RPC_METHOD_JOB_SUBMIT = '$APP_NAME_COMPACT.run';

	/* CLI */
	inline public static var SUBMITTED_JOB_RECORD_FILE = 'job.json';
	inline public static var RESULT_INVALID_JOB_ID = 'invalid_job_id';
	/**
	 * Look for this folder in the working directory all the way down
	 * to the root dir.
	 */
	public static var LOCAL_CONFIG_DIR = '.$APP_NAME_COMPACT';
	inline public static var SERVER_CONNECTION_FILE = 'server_connection.yml';
	inline public static var SERVER_CONFIGURATION_FILE = 'server_configuration.yml';
	public static var SERVER_VAGRANT_DIR = '$LOCAL_CONFIG_DIR/vagrant';
	public static var SERVER_LOCAL_DOCKER_DIR = '$LOCAL_CONFIG_DIR/local';

	/* Workers */
	inline public static var LOCAL_DOCKER_SSH_CONFIG_PATH = '/usr/local/etc/ssh/sshd_config';
	inline public static var WORKER_DOCKER_SSH_CONFIG_PATH = '/etc/ssh/sshd_config';
	inline public static var DOCKER_SSH_CONFIG_SFTP_ADDITION = 'Subsystem sftp internal-sftp';
	/* We guess how much the OS of CoreOS uses, and subtract this from total memory */
	inline public static var WORKER_COREOS_OS_MEMORY_USAGE = 2048;//mb
	inline public static var WORKER_JOB_DEFAULT_MEMORY_REQUIRED = 512;//mb

	/* docker */
	inline public static var LOCAL_STORAGE_VOLUME = 'ccc-local-storage';


#if (nodejs && !macro)
	public static var ROOT = (js.Node.process.platform == "win32") ? js.Node.process.cwd().split(js.node.Path.sep)[0] : "/";
#end

	/* Testing only, IPC */
	inline public static var IPC_MESSAGE_READY = 'READY';
}