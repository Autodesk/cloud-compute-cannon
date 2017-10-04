package ccc;

typedef BatchProcessRequestTurboV2 = {
	@:optional var id :JobId;
	@:optional var inputs :Array<ComputeInputSource>;
	@:optional var image :String;
#if clientjs
	@:optional var imagePullOptions :Dynamic;
#else
	@:optional var imagePullOptions :PullImageOptions;
#end
	@:optional var command :Array<String>;
	@:optional var workingDir :String;
	@:optional var parameters :JobParams;
	@:optional var inputsPath :String;
	@:optional var outputsPath :String;
	@:optional var meta :Dynamic<String>;
	/* We can save time if outputs are ignored */
	@:optional var ignoreOutputs :Bool;
	@:optional var CreateContainerOptions:CreateContainerOptions;
}
