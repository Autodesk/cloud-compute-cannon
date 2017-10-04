package ccc.compute.shared;

/**
 * These are key status events logged
 * that we can monitor in the logging
 * aggregator.
 */
@:enum
abstract LogEventType(String) to String
{
	var ServerStarted = 'ServerStarted';
	var LogLevel = 'LogLevel';
	var ServerReady = 'ServerReady';
	var JobSubmitted = 'JobSubmitted';
	var JobAddedToQueue = 'JobAddedToQueue';
	var JobStart = 'JobStart';
	var JobEnd = 'JobEnd';
	var JobError = 'JobError';
	var WorkerCreated = 'WorkerCreated';
	var WorkerProcessStarted = 'WorkerProcessStarted';
	var WorkerTerminated = 'WorkerTerminated';
	var WorkerHealthOk = 'WorkerHealthOk';
	var WorkerHealthBad = 'WorkerHealthBad';
	var MonitorRequestReturnedOk = 'MonitorRequestReturnedOk';
	var MonitorRequestReturnedError = 'MonitorRequestReturnedError';
	var WorkersScaleUp = 'WorkersScaleUp';
	var WorkersScaleDown = 'WorkersScaleDown';
	var WorkersDesiredCapacity = 'WorkersDesiredCapacity';
}

class LogEvents
{
	static var EVENT_KEY = 'event';
	inline public static function add(logBlob :Dynamic, e :LogEventType) :Dynamic
	{
		Reflect.setField(logBlob, EVENT_KEY, e);
		return logBlob;
	}
}
