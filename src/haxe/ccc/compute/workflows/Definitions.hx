package ccc.compute.workflows;

import haxe.DynamicAccess;

abstract WorkflowId(String) to String from String
{
	inline function new (s: String)
		this = s;
}

@:enum
abstract WorkflowState(String) to String from String {
	var Running = 'running';
	var Finished = 'finished';
	var None = 'none';
}


typedef WorkflowTransform = {
	var image :String;
	var command :Array<String>;
	@:optional var env :DynamicAccess<String>;
}

typedef WorkflowPipeTransform = {
	var name :String;
	var input :String;
	var output :String;
}

typedef WorkflowPipeSource = {
	//Either one of these types
	@:optional var file :String;
	@:optional var transform :String;
	@:optional var output :String;
}

typedef WorkflowPipeTarget = {
	var transform :String;
	var input :String;
}

typedef WorkflowPipe = {
	var source :WorkflowPipeSource;
	var target :WorkflowPipeTarget;
}

typedef WorkflowDefinition = {
	var transforms :DynamicAccess<WorkflowTransform>;
	var pipes :Array<WorkflowPipe>;
}

typedef WorkflowResult = {
	var output :DynamicAccess<String>;
	@:optional var error :Dynamic;
	var pipes :Array<WorkflowPipe>;
}