package ccc;

typedef WorkerStatusJob = {
	var id :JobId;
	var enqueued :String;
	var started :String;
	var duration :String;
	var state :JobWorkingStatus;
	var attempts :Int;
	var image :String;
}
