package ccc;

typedef JobResultsTurbo = {
	var id :JobId;
	var stdout :Array<String>;
	var stderr :Array<String>;
	var exitCode :Int;
	var outputs :DynamicAccess<String>;
	@:optional var error :Dynamic;
	@:optional var stats :JobResultsTurboStats;
}
