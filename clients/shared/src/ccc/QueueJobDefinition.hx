package ccc;

import haxe.extern.EitherType;

/**
 * Placed on the Bull queue
 */
typedef QueueJobDefinition<T:(EitherType<DockerBatchComputeJob,BatchProcessRequestTurboV2>)> = {
	var id :JobId;
	var type :QueueJobDefinitionType;
	var item :T;
	var parameters :JobParams;
	var priority :Bool;
	var attempt :Int;
}