package ccc;

/**
 * Example:
 * {
	jobId : asd74gf,
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
	var jobId :JobId;
	@:optional var status :JobFinishedStatus;
	@:optional var exitCode :Int;
	@:optional var stdout :String;
	@:optional var stderr :String;
	@:optional var resultJson :String;
	@:optional var inputsBaseUrl :String;
	@:optional var inputs :Array<String>;
	@:optional var outputsBaseUrl :String;
	@:optional var outputs :Array<String>;
	@:optional var error :Dynamic;
	@:optional var stats :PrettyStatsData;
	@:optional var definition :DockerBatchComputeJob;
	// @:optional 
	// var baseUrl :String;
}