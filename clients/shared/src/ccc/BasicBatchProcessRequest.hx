package ccc;

//TODO: this should extend (or somehow use the Definitions.DockerBatchComputeJob)
typedef BasicBatchProcessRequest = {
	@:optional var inputs :Array<ComputeInputSource>;
	@:optional var image :String;
#if clientjs
	@:optional var createOptions :Dynamic;
	@:optional var pull_options :Dynamic;
#else
	@:optional var createOptions :CreateContainerOptions;
	@:optional var pull_options :PullImageOptions;
#end
	@:optional var cmd :Array<String>;
	@:optional var workingDir :String;
	@:optional var parameters :JobParams;
	@:optional var md5 :String;
	@:optional var containerInputsMountPath :String;
	@:optional var containerOutputsMountPath :String;
	/* Stores the stdout, stderr, and result.json */
	@:optional var resultsPath :String;
	@:optional var inputsPath :String;
	@:optional var outputsPath :String;
	@:optional var contextPath :String;
	/* Returns the result.json when the job is finished */
	@:optional var wait :Bool;
	/* Metadata logged and saved in the job definition and results.json  */
	@:optional var meta :Dynamic;
	@:optional var appendStdOut :Bool;
	@:optional var appendStdErr :Bool;
	@:optional var mountApiServer :Bool;
	@:optional var priority :Bool;
	/* No job persistance, no durability, no redis, just speed */
	@:optional var turbo :Bool;
}