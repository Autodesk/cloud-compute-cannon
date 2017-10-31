package ccc;

typedef JobStatusUpdate = {
	var status :JobStatus;
	var statusWorking :JobWorkingStatus;
	var statusFinished :JobFinishedStatus;
	var jobId :JobId;
	@:optional var error :Dynamic;
}
