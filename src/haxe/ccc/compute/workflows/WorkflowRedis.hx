package ccc.compute.workflows;

import js.npm.RedisClient;
import js.npm.redis.RedisLuaTools;

import promhx.RedisPromises;

import util.RedisTools;

@:forward
abstract WorkflowRedis(RedisClient) to RedisClient from RedisClient
{
	inline public static function getChannelKey(id :WorkflowId) :String
	{
		return '${REDIS_KEY_WORKFLOW_STATE_CHANNEL_PREFIX}${id}';
	}

	inline public function removeWorkflow(id :WorkflowId) :Promise<Bool>
	{
		return RedisPromises.hdel(this, REDIS_KEY_WORKFLOW_STATE, id)
			.then(function(_) {
				return true;
			});
	}

	inline public function getWorkflowState(id :WorkflowId) :Promise<WorkflowState>
	{
		return RedisPromises.hget(this, REDIS_KEY_WORKFLOW_STATE, id)
			.then(function(result :String) {
				traceCyan('getWorkflowState id=$id result=$result');
				var state :WorkflowState = result;
				if (state == null) {
					state = WorkflowState.None;
				}
				return state;
			});
	}

	inline public function setWorkflowState(id :WorkflowId, state :WorkflowState) :Promise<Int>
	{
		traceMagenta('setWorkflowState id=$id state=$state');
		return RedisPromises.hset(this, REDIS_KEY_WORKFLOW_STATE, id, state)
			.then(function(_) {
				this.publish(getChannelKey(id), state);
				return _;
			});
	}

	public function onWorkflowFinished(workflowId :String) :{promise:Promise<Bool>, cancel :Void->Void}
	{
		var rand = js.npm.shortid.ShortId.generate();
		var channelKey = getChannelKey(workflowId);
		var stream = RedisTools.createStreamFromHash(this, channelKey, REDIS_KEY_WORKFLOW_STATE, workflowId);
		var cancel = function() {
			traceMagenta('onWorkflowFinished $rand workflowId=$workflowId cancel called');
			stream.end();
		}
		var promise = new DeferredPromise();

		stream.then(function(state :WorkflowState) {
			traceMagenta('onWorkflowFinished $rand workflowId=$workflowId state=$state');
			if (state == WorkflowState.Finished && promise != null) {
				promise.resolve(true);
				promise = null;
				stream.end();
			}
		});
		return {promise:promise.boundPromise, cancel:cancel};
	}
}