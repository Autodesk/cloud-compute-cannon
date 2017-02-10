package ccc.compute.server.stats;

typedef SingleJobExecution = {
	var enqueued :Float;
	var dequeued :Float;
	var copiedInputs :Float;
	var copiedOutputs :Float;
	var copiedImage :Float;
	var copiedInputsAndImage :Float;
	var containerExited :Float;
	var exitCode :Int;
	//These are only needed if requeueing
	@:optional var error :String;
}

typedef StatsData = {
	var requestReceived :Float;
	var requestUploaded :Float;
	var attempts :Array<SingleJobExecution>;
	var finished :Float;
	@:optional var error :String;
}

typedef PrettySingleJobExecution = {
	var enqueued :String;
	var dequeued :String;
	var inputs :String;
	var outputs :String;
	var image :String;
	var inputsAndImage :String;
	var container :String;
	var exitCode :Int;
	//These are only needed if requeueing
	@:optional var error :String;
}
typedef PrettyStatsData = {
	var recieved :String;
	var duration :String;
	var uploaded :String;
	var attempts :Array<PrettySingleJobExecution>;
	var finished :String;
	@:optional var error :String;
}