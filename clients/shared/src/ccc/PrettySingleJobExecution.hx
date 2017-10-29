package ccc;

typedef PrettySingleJobExecution = {
	var enqueued :String;
	var dequeued :String;
	var pending :String;
	var inputs :String;
	var outputs :String;
	var logs :String;
	var image :String;
	var inputsAndImage :String;
	var outputsAndLogs :String;
	var container :String;
	var exitCode :Int;
	//These are only needed if requeueing
	@:optional var error :String;
}
