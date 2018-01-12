package ccc.compute.server.execution;

import js.node.Path;
import js.node.stream.Readable;
import js.node.stream.Writable;
import js.npm.redis.RedisClient;
import js.npm.clicolor.CliColor;
import js.npm.docker.Docker;


import promhx.Promise;
import promhx.RedisPromises;

import util.streams.StreamTools;
import util.CliColors;

using StringTools;

class JobTools
{
	public static function dockerTag(id :JobId) :String
	{
		return id.toString().toLowerCase();
	}

	inline public static function generateJobId() :JobId
	{
		return ComputeTools.createUniqueId();
	}

	inline public static function generateComputeJobId(jobId :JobId, ?attempt :Int = 1) :ComputeJobId
	{
		return '${jobId}${Constants.JOB_ID_ATTEMPT_SEP}${attempt}';
	}

	inline public static function getWorkerVolumeNameInputs(jobId :JobId, attempt :Int) :DockerVolumeName
	{
		return '${DIRECTORY_INPUTS}__${jobId}__${attempt}';
	}

	inline public static function getWorkerVolumeNameOutputs(jobId :JobId, attempt :Int) :DockerVolumeName
	{
		return '${DIRECTORY_OUTPUTS}__${jobId}__${attempt}';
	}

	public static function prependJobResultsUrls(jobResult :JobResult, urlPrefix :String)
	{
		Assert.notNull(jobResult);
		if (jobResult.stdout != null && jobResult.stdout.indexOf('://') == -1) {
			jobResult.stdout = Path.join(urlPrefix, jobResult.stdout);
			jobResult.stderr = Path.join(urlPrefix, jobResult.stderr);
			jobResult.resultJson = Path.join(urlPrefix, jobResult.resultJson);
			jobResult.inputsBaseUrl = Path.join(urlPrefix, jobResult.inputsBaseUrl);
			jobResult.outputsBaseUrl = Path.join(urlPrefix, jobResult.outputsBaseUrl);
		}
	}

	public static function workerInputDir(id :ComputeJobId) :String
	{
		return '$id/$DIRECTORY_INPUTS/';
	}

	public static function workerOutputDir(id :ComputeJobId) :String
	{
		return '$id/$DIRECTORY_OUTPUTS/';
	}

	public static function workerStdoutDir(id :ComputeJobId) :String
	{
		return '$id/';
	}

	public static function workerStdoutPath(id :ComputeJobId) :String
	{
		return '${workerStdoutDir(id)}${STDOUT_FILE}';
	}

	public static function workerStderrPath(id :ComputeJobId) :String
	{
		return '${workerStdoutDir(id)}${STDERR_FILE}';
	}

	public static function inputDir(job :DockerBatchComputeJob) :String
	{
		Assert.notNull(job);
		Assert.notNull(job.id);
		if (job.inputsPath.isEmpty()) {
			return defaultInputDir(job.id);
		} else {
			return job.inputsPath.ensureEndsWith('/').removePrefix('/');
		}
	}

	public static function outputDir(job :DockerBatchComputeJob) :String
	{
		Assert.notNull(job);
		Assert.notNull(job.id);
		if (job.outputsPath.isEmpty()) {
			return defaultOutputDir(job.id);
		} else {
			return job.outputsPath.ensureEndsWith('/').removePrefix('/');
		}
	}

	public static function resultDir(job :DockerBatchComputeJob) :String
	{
		Assert.notNull(job);
		Assert.notNull(job.id);
		if (job.resultsPath.isEmpty()) {
			return job.id + '/';
		} else {
			return job.resultsPath.ensureEndsWith('/').removePrefix('/');
		}
	}

	public static function resultJsonPath(job :DockerBatchComputeJob) :String
	{
		return '${resultDir(job)}${RESULTS_JSON_FILE}';
	}

	public static function resultJsonPathFromJobId(jobId :JobId) :String
	{
		return '${jobId}/${RESULTS_JSON_FILE}';
	}

	public static function stdoutPath(job :DockerBatchComputeJob) :String
	{
		return '${resultDir(job)}${STDOUT_FILE}';
	}

	public static function stderrPath(job :DockerBatchComputeJob) :String
	{
		return '${resultDir(job)}${STDERR_FILE}';
	}

	public static function defaultInputDir(id :JobId) :String
	{
		return Path.join(id, DIRECTORY_INPUTS).ensureEndsWith('/');
	}

	public static function defaultOutputDir(id :JobId) :String
	{
		return Path.join(id, DIRECTORY_OUTPUTS).ensureEndsWith('/');
	}

	public static function getJobColor(jobId :JobId) :String
	{
		return CliColors.colorFromString(jobId);
	}

	public static function getJobLog(jobId :JobId) :String->Void
	{
		var transform = getJobStdOutTransform(jobId);
		return function(s) {
			js.Node.process.stdout.write(transform(s) + '\n');
		};
	}

	public static function getJobErrLog(jobId :JobId) :Dynamic->Void
	{
		var transform = getJobStdErrTransform(jobId);
		return function(s) {
			js.Node.process.stderr.write(transform(s) + '\n');
		};
	}

	public static function getJobStdOutTransform(jobId :JobId) :Dynamic->String
	{
		var jobIdShort = jobId.toString().substr(0, 8);
		var jobPrefix = '[JOB:$jobIdShort] ';

		//Colorize
		var colorConvert :String->String = CliColors.colorTransformFromString(jobId);
		return function(s) {
			return colorConvert(jobPrefix + s);
		};
	}

	public static function getJobStdErrTransform(jobId :JobId) :Dynamic->String
	{
		var jobIdShort = jobId.toString().substr(0, 8);
		var jobPrefix = '[JOB:$jobIdShort ERROR] ';
		var colorConvert :String->String = CliColors.colorTransformFromString(jobId);
		return function(s) {
			return colorConvert(jobPrefix) + CliColor.bold(CliColor.red(s));
		};
	}
}