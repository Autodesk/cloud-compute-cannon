package ccc;

typedef SingleJobExecution = {
	var worker :MachineId;
	var containerId :String;
	var enqueued :Float;
	var dequeued :Float;
	var copiedInputs :Float;
	var copiedOutputs :Float;
	var copiedLogs :Float;
	var copiedImage :Float;
	var copiedInputsAndImage :Float;
	var containerExited :Float;
	var exitCode :Int;
	var statusWorking :JobWorkingStatus;
	//This are only needed if requeueing
	@:optional var error :String;
}