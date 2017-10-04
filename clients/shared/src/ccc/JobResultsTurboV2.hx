package ccc;

typedef JobResultsTurboV2 = {
	var id :JobId;
	var stdout :Array<String>;
	var stderr :Array<String>;
	var exitCode :Int;
	var outputs :Array<ComputeInputSource>;
	@:optional var error :Dynamic;
	@:optional var stats :JobResultsTurboStats;
}