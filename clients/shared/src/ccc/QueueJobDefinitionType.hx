package ccc;

@:enum
abstract QueueJobDefinitionType(String) from String to String {
	var turbo = 'turbo';
	var compute = 'compute';
}
