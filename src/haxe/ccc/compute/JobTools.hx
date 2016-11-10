package ccc.compute;

import ccc.compute.JobTools;

import js.node.Path;
import js.node.stream.Readable;
import js.node.stream.Writable;
import js.npm.RedisClient;
import js.npm.clicolor.CliColor;
import js.npm.docker.Docker;


import promhx.Promise;
import promhx.RedisPromises;

import util.streams.StreamTools;
import util.streams.StdStreams;
import util.CliColors;

using ccc.compute.ComputeTools;
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

	inline public static function getWorkerVolumeNameInputs(computeJobId :ComputeJobId) :DockerVolumeName
	{
		return '${DIRECTORY_INPUTS}__${computeJobId}';
	}

	inline public static function getWorkerVolumeNameOutputs(computeJobId :ComputeJobId) :DockerVolumeName
	{
		return '${DIRECTORY_OUTPUTS}__${computeJobId}';
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

	public static function inputDir(job :DockerJobDefinition) :String
	{
		Assert.notNull(job);
		Assert.notNull(job.jobId);
		if (job.inputsPath == null) {
			return defaultInputDir(job.jobId);
		} else {
			return job.inputsPath.ensureEndsWith('/');
		}
	}

	public static function outputDir(job :DockerJobDefinition) :String
	{
		Assert.notNull(job);
		Assert.notNull(job.jobId);
		if (job.outputsPath == null) {
			return defaultOutputDir(job.jobId);
		} else {
			return job.outputsPath.ensureEndsWith('/');
		}
	}

	public static function resultDir(job :DockerJobDefinition) :String
	{
		Assert.notNull(job);
		Assert.notNull(job.jobId);
		if (job.resultsPath.isEmpty()) {
			return job.jobId + '/';
		} else {
			return job.resultsPath.ensureEndsWith('/');
		}
	}

	public static function resultJsonPath(job :DockerJobDefinition) :String
	{
		return resultDir(job) + RESULTS_JSON_FILE;
	}

	public static function stdoutPath(job :DockerJobDefinition) :String
	{
		return '${resultDir(job)}${STDOUT_FILE}';
	}

	public static function stderrPath(job :DockerJobDefinition) :String
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

	public static function getStreams(jobId :JobId, ?pipeToConsole :Bool = true) :LogStreams
	{
		//stdout
		var stdOutStream = StreamTools.createTransformStream(getJobStdOutTransform(jobId));
		stdOutStream.pipe(js.Node.process.stdout);
		stdOutStream.on(WritableEvent.Finish, function() {
			stdOutStream.unpipe();
		});

		//stderr
		var stdErrStream = StreamTools.createTransformStream(getJobStdErrTransform(jobId));
		stdErrStream.pipe(js.Node.process.stderr);
		stdErrStream.on(WritableEvent.Finish, function() {
			stdErrStream.unpipe();
		});

		//process
		var processStdStream = StreamTools.createTransformStream(getJobStdOutTransform(jobId));
		processStdStream.pipe(js.Node.process.stdout);
		processStdStream.on(WritableEvent.Finish, function() {
			processStdStream.unpipe();
		});
		var processErrorStream = StreamTools.createTransformStream(getJobStdErrTransform(jobId));
		processErrorStream.pipe(js.Node.process.stdout);
		processErrorStream.on(WritableEvent.Finish, function() {
			processErrorStream.unpipe();
		});

		var computeStdStreams :StdStreams = {out:cast stdOutStream, err:cast stdErrStream};
		var processStdStreams :StdStreams = {out:cast processStdStream, err:cast processErrorStream};
		return {compute:computeStdStreams, process:processStdStreams};
	}
}