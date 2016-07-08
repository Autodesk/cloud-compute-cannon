package ccc.compute;

#if (nodejs && !macro)
	import js.npm.Docker;
	import js.npm.Ssh;
	import js.npm.PkgCloud.ProviderCredentials;

	import ccc.storage.ServiceStorage;
	import ccc.storage.StorageTools;
#end

import t9.abstracts.time.Minutes;
import t9.abstracts.net.*;

using StringTools;

/**
 *********************************************
 * JOB DEFINITIONS
 **********************************************
 */

/**
 * Id for a job submitted to the queue
 */
abstract JobId(String) to String from String
{
	inline public function new (s: String)
		this = s;

	inline public function toString() :String
	{
		return this;
	}
}

/**
 * Id for an attempt of an actual job run. If a job fails
 * and is retried, the second attempt will have a new ComputeJobId
 */
abstract ComputeJobId(String) to String from String
{
	inline function new (s: String)
		this = s;
}

@:enum
abstract JobPathType(String) {
	var Inputs = 'inputs';
	var Outputs = 'outputs';
	var Results = 'results';
}

/**
 * I'm expecting this typedef to include:
 * memory contraints
 * CPU/GPU constraints
 * storage constraints
 */
typedef JobParams = {
	var maxDuration :Float;//Milliseconds
	var cpus :Int;
}

/* Submission definitions */

@:enum
abstract InputSource(String) {
	var InputUrl = 'url';
	var InputInline = 'inline';
	var InputStream = 'stream';
}

typedef ComputeInputSource = {
	var type :InputSource;
	var value :Dynamic;
	var name :String;
	@:optional var encoding :String;
}

//TODO: this should extend (or somehow use the Definitions.DockerBatchComputeJob)
typedef BasicBatchProcessRequest = {
	@:optional var inputs :Array<ComputeInputSource>;
	@:optional var image :String;
	@:optional var cmd :Array<String>;
	@:optional var workingDir :String;
	@:optional var parameters :JobParams;
	@:optional var md5 :String;
	/* Stores the stdout, stderr, and result.json */
	@:optional var resultsPath :String;
	@:optional var inputsPath :String;
	@:optional var outputsPath :String;
	@:optional var contextPath :String;
}


/**
 *********************************************
 * DOCKER DEFINITIONS
 **********************************************
 */

@:enum
abstract DockerImageSourceType(String) {
	var Image = 'image';
	var Context = 'context';
}

typedef DockerImageSource = {
	var type :DockerImageSourceType;
	@:optional var value :String;//If an image, image name, if a context, the URL of the path
#if (nodejs && !macro)
	@:optional var options :BuildImageOptions;
#else
	@:optional var options :Dynamic;
#end
}

/**
 * This is the json (persisted in the db)
 * representing the docker job.
 */
typedef DockerBatchComputeJob = {
	var image :DockerImageSource;
	@:optional var inputs :Array<String>;
	@:optional var command :Array<String>;
#if nodejs
	@:optional var meta :TypedDynamicObject<String,String>;
#else
	@:optional var meta :Dynamic<String>;
#end
	@:optional var workingDir :String;
	/**
	 * Only specify the inputsPath, outputsPath,
	 * or resultsPath if you have a reason to change
	 * the defaults.
	 */
	@:optional var inputsPath :String;
	@:optional var outputsPath :String;
	/* Stores the stdout, stderr, and result.json. */
	@:optional var resultsPath :String;
}


typedef DockerJobDefinition = {>DockerBatchComputeJob,
	@:optional var computeJobId :ComputeJobId;
	var jobId :JobId;
	@:optional var worker :WorkerDefinition;
}

/********************************************/

typedef ProviderConfigBase = {
	var maxWorkers :Int;
	var minWorkers :Int;
	var priority :Int;
	var billingIncrement :Minutes;
}

typedef InstanceDefinition = {
	var id :MachineId;
	var hostPublic :HostName;
	var hostPrivate :HostName;
#if nodejs
	var ssh :ConnectOptions;
	var docker :ConstructorOpts;
#else
	var ssh :Dynamic;
	var docker :Dynamic;
#end
}

typedef WorkerDefinition = {>InstanceDefinition,
	@:optional var meta :Dynamic;
}

//TODO:memory, gpu, etc
typedef WorkerParameters = {
	var cpus :Int;
	var memory :Int;//Megabytes
}

abstract MachineId(String) to String from String
{
	inline public function new (s: String)
	{
		this = s;
	}
}

abstract MachinePoolId(String) to String
{
	inline public function new (s: String)
	{
		this = s;
	}

	@:from
	inline static public function fromString (s: String)
	{
		return new MachinePoolId(s);
	}
}

@:enum
abstract JobStatus(String) from String {
	/**
	 * The job is in the queue.
	 * Set in Redis, not handled elsewhere.
	 */
	var Pending = 'pending';
	/**
	 * The job is loaded, inputs, copied, etc.
	 * The JobWorkingStatus tracks the granular working process.
	 * Set in Redis, not handled elsewhere.
	 */
	var Working = 'working';
	/**
	 * The JobFinishedStatus gets set here. The Job object then handles
	 * that status before marking the job as finished.
	 */
	var Finalizing = 'finalizing';
	/**
	 * When the Job object is finished finalizing the job, it marks
	 * the job as finished.
	 */
	var Finished = 'finished';
}

/**
 * Used by BatchComputeDocker for resuming in case the process dies.
 */
@:enum
abstract JobWorkingStatus(String) from String to String {
	var None = 'none';
	var Failed = 'failed';
	var Cancelled = 'cancelled';
	var CopyingInputs = 'copying_inputs';
	var CopyingImage = 'copying_image';
	var ContainerRunning = 'container_running';
	var CopyingOutputs = 'copying_outputs';
	var CopyingLogs = 'copying_logs';
	var FinishedWorking = 'finished_working';
}

typedef BatchJobResult = {
	var exitCode :Int;
	var copiedLogs :Bool;
	@:optional var JobWorkingStatus :JobWorkingStatus;
	@:optional var outputFiles :Array<String>;
	@:optional var error :Dynamic;
}

@:enum
abstract JobFinishedStatus(String) from String {
	/**
	 * Success simply means the docker container ran, then eventually exited.
	 * The container can exit with a non-zero exit code, this is still
	 * considered a 'success'.
	 */
	var Success = 'success';
	/**
	 * Long running jobs will be killed
	 */
	var TimeOut = 'timeout';
	/** A failed job means that there is some user error or system error
	 *  that prevents the docker container starting, or an error
	 *  ruuing or copying job data. For example, relying
	 *  on a docker image that does not exist.
	 */
	var Failed = 'failed';
	/**
	 * Users can kill jobs.
	 */
	var Killed = 'killed';

	/**
	 * Placeholder initialized status. It means the job is NOT finished.
	 */
	var None = 'none';
}

typedef JobStatusUpdate = {
	var JobStatus :JobStatus;
	var JobFinishedStatus :JobFinishedStatus;
	var jobId :JobId;
	@:optional var computeJobId :ComputeJobId;
	@:optional var error :Dynamic;
	@:optional var job :DockerJobDefinition;
}


/**
 * Example:
 * {
	id : 3519F65B-10EA-46F3-92F8-368CF377DFCF,
	status : Success,
	exitCode : 0,
	stdout : https://s3-us-west-1.amazonaws.com/bionano-platform-test/3519F65B-10EA-46F3-92F8-368CF377DFCF/stdout,
	stderr : https://s3-us-west-1.amazonaws.com/bionano-platform-test/3519F65B-10EA-46F3-92F8-368CF377DFCF/stderr,
	resultJson : https://s3-us-west-1.amazonaws.com/bionano-platform-test/3519F65B-10EA-46F3-92F8-368CF377DFCF/result.json,
	inputsBaseUrl : https://s3-us-west-1.amazonaws.com/bionano-platform-test/3519F65B-10EA-46F3-92F8-368CF377DFCF/inputs/,
	outputsBaseUrl : https://s3-us-west-1.amazonaws.com/bionano-platform-test/3519F65B-10EA-46F3-92F8-368CF377DFCF/outputs/,
	inputs : [script.sh],
	outputs : [bar]
}
 */
typedef JobResult = {
	var id :JobId;
	var status :JobFinishedStatus;
	var exitCode :Int;
	var stdout :String;
	var stderr :String;
	var resultJson :String;
	@:optional var inputsBaseUrl :String;
	@:optional var inputs :Array<String>;
	@:optional var outputsBaseUrl :String;
	@:optional var outputs :Array<String>;
	@:optional var error :Dynamic;
}


/**
 *********************************************
 * CORE DEFINITIONS
 **********************************************
 */

typedef QueueJob<T> = {
	var id :JobId;
	var item :T;
	var parameters :JobParams;
}

/**
 * This is only used by ComputeQueue.getJobDescription
 * and returns a combination of the data in the redis
 * db: item, id, stats, assigned worker.
 */
typedef QueueJobDefinition<T> = {
	var id :JobId;
	var item :T;
	var parameters :JobParams;
	@:optional var computeJobId :ComputeJobId;
	@:optional var worker :WorkerDefinition;
	@:optional var stats :Array<Float>;
}

typedef QueueJobDefinitionDocker=QueueJobDefinition<DockerJobDefinition>;

typedef JobDescriptionComplete = {
	var definition :DockerJobDefinition;
	var status :JobStatus;
	@:optional var result :JobResult;
}

/**
 *********************************************
 * Submission definitions
 **********************************************
 */


typedef BasicBatchProcessResponse = {
	var jobId :JobId;
}

typedef BasicBatchProcessResponseFull = {>BasicBatchProcessResponse,
	var url :String;
	var files :Array<String>;
	var statusCode :Int;
}

/**
 *********************************************
 * CLI definitions
 **********************************************
 */

typedef ServerConnectionBlob = {
	var host :Host;
	/**
	 * If server is missing, the server ssh config is pulled from ~/.ssh/config
	 */
	@:optional var server :InstanceDefinition;
	@:optional var provider: ServiceConfiguration;
}

typedef ServerVersionBlob = {
	var npm :String;
	var compiler :String;
	var instance :String;
	@:optional var VERSION :String;
}

typedef ClientVersionBlob = {
	var npm :String;
	var compiler :String;
}

@:enum
abstract JobCLICommand(String) from String {
	var Remove = 'remove';
	var Status = 'status';
	var ExitCode = 'exitcode';
	var Kill = 'kill';
	var Result = 'result';
	var Definition = 'definition';
	var JobStats = 'stats';
	var Time = 'time';
}

enum CLIResult {
	PrintHelp;
	PrintHelpExit1;
	ExitCode(code :Int);
	Success;
}

abstract CLIServerPathRoot(String) from String
{
	inline public function new(s :String)
		this = s;

	inline public function getServerJsonConfigPath() :String
	{
		return js.node.Path.join(this, Constants.LOCAL_CONFIG_DIR, Constants.SERVER_CONNECTION_FILE);
	}

	inline public function getServerJsonConfigPathDir() :String
	{
		return js.node.Path.join(this, Constants.LOCAL_CONFIG_DIR);
	}

	inline public function getLocalServerPath() :String
	{
		return js.node.Path.join(this, Constants.SERVER_LOCAL_DOCKER_DIR);
	}

	inline public function localServerPathExists() :Bool
	{
		var p = getLocalServerPath();
		try {
			var stats = js.node.Fs.statSync(p);
			return true;
		} catch (err :Dynamic) {
			return false;
		}
	}

	

	public function toString() :String
	{
		return this;
	}
}

typedef ServerCheckResult = {
	@:optional var ok :Bool;
	@:optional var connection_file_path :String;
	@:optional var server_id :String;
	@:optional var server_host :String;
	@:optional var http_api_url :String;
	@:optional var status_check_success :{ssh:Bool,docker_compose:Bool,http_api:Bool};
	@:optional var error :Dynamic;
}

typedef ServiceConfiguration = {
	@:optional var server: ServiceConfigurationServer;
	@:optional var providers: Array<ServiceConfigurationWorkerProvider>;
}

typedef ENV = {
	@:optional var PORT: Int;
	@:optional var REDIS_PORT: Int;
	@:optional var REDIS_HOST: String;
}

typedef ServiceConfigurationServer = {
	@:optional var storage: ServiceConfigurationStorage;
}

typedef ServiceConfigurationStorage = {
	var type: String;
	@:optional var rootPath: String;
	@:optional var defaultContainer :String;
	@:optional var credentials :#if nodejs ProviderCredentials #else Dynamic #end;
	@:optional var httpAccessUrl :String;
}

/* This is only used when creating worker providers in code */
@:enum
abstract ServiceWorkerProviderType(String) {
  var boot2docker = "Boot2Docker";
  var vagrant = "Vagrant";
  var pkgcloud = "PkgCloud";
  var mock = "Mock";
}

typedef ServiceConfigurationWorkerProvider = {>ProviderConfigBase,
	var type: ServiceWorkerProviderType;
}