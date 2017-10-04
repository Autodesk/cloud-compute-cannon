package ccc;

@:enum
abstract ServerEventType(String) from String to String {
	var STARTED = 'STARTED';
	var READY = 'READY';
}