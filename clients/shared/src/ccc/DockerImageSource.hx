package ccc;

import js.npm.docker.Docker;

typedef DockerImageSource = {
	var type :DockerImageSourceType;
	@:optional var value :String;//If an image, image name, if a context, the URL of the path
#if (nodejs && !macro && !clientjs)
	@:optional var optionsBuild :BuildImageOptions;
	@:optional var optionsCreate :CreateContainerOptions;
	@:optional var pull_options :PullImageOptions;
#else
	@:optional var pull_options :Dynamic;
	@:optional var optionsBuild :Dynamic;
	@:optional var optionsCreate :Dynamic;
#end
}