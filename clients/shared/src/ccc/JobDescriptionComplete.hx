package ccc;

typedef JobDescriptionComplete = {
	var definition :DockerBatchComputeJob;
	var status :JobStatus;
	@:optional var result :JobResult;
}