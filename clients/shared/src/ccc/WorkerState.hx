package ccc;

typedef WorkerState = {
	var starts :Array<Float>;
	var id :MachineId;
	var DockerInfo :Dynamic;
	var diskTotal: Float;
	var diskUsed: Float;
	var status :WorkerStatus;
	var statusHealth :WorkerHealthStatus;
	var statusTime :Float;
	var events :Array<WorkerEvent>;
	/* Debug commands can be sent, and will be packaged with the update data */
	@:optional var command :WorkerUpdateCommand;
}