package ccc;

@:enum
abstract WorkerUpdateCommand(String) from String to String {
	var HealthCheck = 'HealthCheck';
	var HealthCheckPerformed = 'HealthCheckPerformed';
	var PauseHealthCheck = 'PauseHealthCheck';
	var UnPauseHealthCheck = 'UnPauseHealthCheck';
	var UpdateReasonTermination = 'UpdateReasonTermination';
	var UpdateReasonInitializing = 'UpdateInitializing';
	var UpdateReasonToHealthy = 'UpdateReasonToHealthy';
	var UpdateReasonToUnHealthy = 'UpdateReasonToUnHealthy';

}