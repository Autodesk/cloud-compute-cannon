package ccc;

import haxe.extern.EitherType;

/**
 * Placed on the Bull queue
 */
typedef QueueJobDefinition = {
	var id :JobId;
	var type :QueueJobDefinitionType;
	var item :EitherType<DockerBatchComputeJob,BatchProcessRequestTurboV2>;
	var parameters :JobParams;
	@:optional var priority :Bool;
	var attempt :Int;
}