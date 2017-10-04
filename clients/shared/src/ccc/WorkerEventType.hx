package ccc;

@:enum
abstract WorkerEventType(String) from String to String {
	var INIT = 'INIT';
	var START = 'START';
	var UNHEALTHY = 'UNHEALTHY';
	var HEALTHY = 'HEALTHY';
	var TERMINATE = 'TERMINATE';
}