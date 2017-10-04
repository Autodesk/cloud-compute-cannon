package ccc.compute.worker;

@:enum
abstract RedisError(String) to String from String {
	var NoJobFound = 'NoJobFound';
	var JobAlreadyFinished = 'JobAlreadyFinished';
	var NoAttemptFound = 'NoAttemptFound';
}