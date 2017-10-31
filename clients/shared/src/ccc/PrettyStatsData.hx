package ccc;

typedef PrettyStatsData = {
	var recieved :String;
	var duration :String;
	var uploaded :String;
	var attempts :Array<PrettySingleJobExecution>;
	var finished :String;
	@:optional var error :String;
}
