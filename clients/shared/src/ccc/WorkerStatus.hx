package ccc;

@:enum
abstract WorkerStatus(String) from String to String {
	var OK = 'OK';
	var UNHEALTHY = 'UNHEALTHY';
	var REMOVED = 'REMOVED';
}