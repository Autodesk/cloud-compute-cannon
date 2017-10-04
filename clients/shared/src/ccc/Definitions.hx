package ccc;

// import ccc.compute.shared.Constants.*;
// import ccc.compute.worker.job.stats.StatsDefinitions;

// import js.npm.docker.Docker;

import haxe.Json;
import haxe.DynamicAccess;

import util.ObjectTools;

import t9.abstracts.time.*;
import t9.abstracts.net.*;

// import ccc.compute.shared.Constants.*;

// #if (nodejs && !macro && !clientjs)
// 	import js.npm.docker.Docker;
// 	import js.npm.ssh2.Ssh;
// 	import js.npm.pkgcloud.PkgCloud.ProviderCredentials;
// 	import js.npm.PkgCloudHelpers;

// 	import ccc.storage.StorageDefinition;
// 	import ccc.storage.ServiceStorage;
// 	import ccc.storage.StorageTools;
// #end

using StringTools;

typedef WorkerStateInternal = {
	var ncpus :Int;
	var health :WorkerHealthStatus;
	var timeLastHealthCheck :Date;
	var jobs :Array<JobId>;
	var id :MachineId;
}

@:enum
abstract DistributedTaskType(String) from String to String {
	var CheckAllWorkerHealth = 'CheckAllWorkerHealth';
	var RunScaling = 'RunScaling';
}

typedef WorkerCount=Int;
typedef WorkerPoolPriority=Int;
typedef MachineStatus=String;

/**
 *********************************************
 * JOB DEFINITIONS
 **********************************************
 */

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

/* Submission definitions */

typedef JobResultsTurboStats = {
	var ensureImage :String;
	var copyInputs :String;
	var containerCreation :String;
	var containerExecution :String;
	var copyLogs :String;
	var copyOutputs :String;
	var total :String;
}

/**
 * This enumerates all the possible error conditions that will return
 * a 400 status code on job requests or results requests.
 */
@:enum
abstract JobSubmissionError(String) to String from String {
	var Docker_Image_Unknown = 'Docker_Image_Unknown';
}

/**
 *********************************************
 * DOCKER DEFINITIONS
 **********************************************
 */

// typedef DockerJobDefinition = {>DockerBatchComputeJob,
// 	@:optional var computeJobId :ComputeJobId;
// 	@:optional var worker :WorkerDefinition;
// }

/********************************************/

typedef WorkerDefinition = {>InstanceDefinition,
	@:optional var meta :Dynamic;
}

//TODO:memory, gpu, etc
typedef WorkerParameters = {
	var cpus :Int;
	var memory :Int;//Megabytes
}

abstract MachinePoolId(String) to String
{
	inline public function new (s: String)
	{
		this = s;
	}
}

/**
 * Used to bundle together the entire status
 */
typedef JobStatusBlob = {
	var status :JobStatus;
	var statusWorking :JobWorkingStatus;
}

typedef BatchJobResult = {
	var exitCode :Int;
	var copiedLogs :Bool;
	@:optional var JobWorkingStatus :JobWorkingStatus;
	@:optional var outputFiles :Array<String>;
	@:optional var error :Dynamic;
	var timeout :Bool;
}

// @:enum
// abstract JobFinishedStatus(String) from String to String {
// 	/**
// 	 * Success simply means the docker container ran, then eventually exited.
// 	 * The container can exit with a non-zero exit code, this is still
// 	 * considered a 'success'.
// 	 */
// 	var Success = 'success';
// 	/**
// 	 * Long running jobs will be killed
// 	 */
// 	var TimeOut = 'timeout';
// 	* A failed job means that there is some user error or system error
// 	 *  that prevents the docker container starting, or an error
// 	 *  ruuing or copying job data. For example, relying
// 	 *  on a docker image that does not exist.
	 
// 	var Failed = 'failed';
// 	/**
// 	 * Users can kill jobs.
// 	 */
// 	var Killed = 'killed';

// 	/**
// 	 * Placeholder initialized status. It means the job is NOT finished.
// 	 */
// 	var None = 'none';
// }

typedef JobStatusUpdate = {
	var status :JobStatus;
	var statusWorking :JobWorkingStatus;
	var statusFinished :JobFinishedStatus;
	var jobId :JobId;
	@:optional var error :Dynamic;
}


typedef PrettySingleJobExecution = {
	var enqueued :String;
	var dequeued :String;
	var pending :String;
	var inputs :String;
	var outputs :String;
	var logs :String;
	var image :String;
	var inputsAndImage :String;
	var outputsAndLogs :String;
	var container :String;
	var exitCode :Int;
	//These are only needed if requeueing
	@:optional var error :String;
}
typedef PrettyStatsData = {
	var recieved :String;
	var duration :String;
	var uploaded :String;
	var attempts :Array<PrettySingleJobExecution>;
	var finished :String;
	@:optional var error :String;
}

typedef SystemStatus = {
	var pendingTop5 :Array<JobId>;
	var pendingCount :Int;
	var workers :Array<{id :MachineId, jobs:Array<{id:JobId,enqueued:String,started:String,duration:String}>,cpus:String}>;
	var finishedTop5 :TypedDynamicObject<JobFinishedStatus,Array<JobId>>;
	var finishedCount :Int;
}

typedef WorkerStatusJob = {
	var id :JobId;
	var enqueued :String;
	var started :String;
	var duration :String;
	var state :JobWorkingStatus;
	var attempts :Int;
	var image :String;
}

// typedef WorkerStatus = {
// 	var jobs :Array<JobStatsData>;
// 	var cpus :Int;
// 	@:optional var id :MachineId;
// 	var healthStatus :WorkerHealthStatus;
// 	var timeLastHealthCheck :String;
// }

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

typedef JobDescriptionComplete = {
	var definition :DockerBatchComputeJob;
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


typedef ServerCheckResult = {
	@:optional var ok :Bool;
	@:optional var connection_file_path :String;
	@:optional var server_id :String;
	@:optional var server_host :String;
	@:optional var http_api_url :String;
	@:optional var status_check_success :{ssh:Bool,docker_compose:Bool,http_api:Bool};
	@:optional var error :Dynamic;
}

typedef JobDataBlob = {>JobResult,
	var url :String;
}

