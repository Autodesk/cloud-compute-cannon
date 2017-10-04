package ccc;

@:enum
abstract DockerImageSourceType(String) {
	var Image = 'image';
	var Context = 'context';
}