package ccc;

@:enum
abstract WorkerEventType(String) from String to String {
	var INIT = 'INIT';
	var START = 'START';
	var UNHEALTHY = 'UNHEALTHY';
	var HEALTHY = 'HEALTHY';
	var TERMINATE = 'TERMINATE';
	var SET_WORKER_COUNT = 'SET_WORKER_COUNT';
	var BAD_HEALTH_DETECTED = 'BAD_HEALTH_DETECTED';
}