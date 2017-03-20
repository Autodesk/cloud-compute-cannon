package ccc.compute.workflows;

class Constants
{
	public static var RPC_METHOD_WORKFLOW = 'workflow/run';
	public static var WORKFLOW_JSON_FILE = 'workflow.json';
	public static var WORKFLOW_RESULT_JSON_FILE = 'workflow-result.json';

	//HTTP
	public static var WORKFLOW_HTTP_HEADER_CACHE = 'ccc-workflow-cache';

	//Redis
	inline public static var REDIS_KEY_WORKFLOW_STATE = 'workflow_state';
	inline public static var REDIS_KEY_WORKFLOW_STATE_CHANNEL_PREFIX = 'workflow_state_';
}