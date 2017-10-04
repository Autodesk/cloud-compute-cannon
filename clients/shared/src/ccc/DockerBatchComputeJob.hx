package ccc;

import haxe.DynamicAccess;

/**
 * This is the json (persisted in the db)
 * representing the docker job.
 */
typedef DockerBatchComputeJob = {
	var jobId :JobId;
	var image :DockerImageSource;
	@:optional var inputs :Array<String>;
	@:optional var command :Array<String>;
	@:optional var meta :DynamicAccess<String>;
	@:optional var workingDir :String;
	@:optional var containerInputsMountPath :String;
	@:optional var containerOutputsMountPath :String;
	/**
	 * Only specify the inputsPath, outputsPath,
	 * or resultsPath if you have a reason to change
	 * the defaults.
	 */
	@:optional var inputsPath :String;
	@:optional var outputsPath :String;
	/* Stores the stdout, stderr, and result.json. */
	@:optional var resultsPath :String;
	@:optional var parameters :JobParams;
	@:optional var appendStdOut :Bool;
	@:optional var appendStdErr :Bool;
	@:optional var mountApiServer :Bool;
}