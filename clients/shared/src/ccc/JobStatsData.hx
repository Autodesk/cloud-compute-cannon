package ccc;

typedef JobStatsData = {
	var v :Int;//Data version, higher number takes precedence
	var jobId :JobId;
	var requestReceived :Float;
	var requestUploaded :Float;
	var attempts :Array<SingleJobExecution>;
	var finished :Float;
	var def :DockerBatchComputeJob;
	var status :JobStatus;
	var statusFinished :JobFinishedStatus;
	@:optional var statusWorking :JobWorkingStatus;
	@:optional var error :String;
}