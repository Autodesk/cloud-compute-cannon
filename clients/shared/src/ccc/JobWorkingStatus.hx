package ccc;

/**
 * Used by BatchComputeDocker for resuming in case the process dies.
 */
@:enum
abstract JobWorkingStatus(String) {
	var None = 'none';
	var Failed = 'failed';
	var Cancelled = 'cancelled';
	var CopyingInputs = 'copying_inputs';
	var CopyingImage = 'copying_image';
	var CopyingInputsAndImage = 'copying_inputs_and_image';
	var ContainerStarting = 'container_starting';
	var ContainerRunning = 'container_running';
	var CopyingOutputs = 'copying_outputs';
	var CopyingLogs = 'copying_logs';
	var CopyingOutputsAndLogs = 'copying_outputs_and_logs';
	var FinishedWorking = 'finished_working';
}