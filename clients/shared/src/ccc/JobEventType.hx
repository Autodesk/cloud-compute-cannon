package ccc;

@:enum
abstract JobEventType(String) from String to String {
	var ENQUEUED = 'ENQUEUED';
	var DEQUEUED = 'DEQUEUED';
	var RESTARTED = 'RESTARTED';
	var ERROR = 'ERROR';
	var FINISHED = 'FINISHED';
}