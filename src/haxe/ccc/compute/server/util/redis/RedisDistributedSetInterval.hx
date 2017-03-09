package ccc.compute.server.util.redis;

import js.Node;
import js.npm.RedisClient;
import js.npm.redis.RedisLuaTools;

/**
 * Runs once per interval, regardless of how
 * many connected instances call this
 */
class RedisDistributedSetInterval
{
	@inject public var _redis :RedisClient;
	static var IS_INITIALIZED = false;

	var _taskId :String;
	var _interval :Float;
	var _task :Void->Void;
	var _setIntervalId :Dynamic;

	public function new(taskId :String, interval :Float, task :Void->Void)
	{
		_taskId = taskId;
		_interval = interval;
		_task = task;
	}

	public function initializeTask()
	{
		_setIntervalId = Node.setInterval(function() {
			shouldRun()
				.then(function(run) {
					if (run) {
						_task();
					}
				});
		}, Std.int(_interval));
	}

	public function dispose()
	{
		Node.clearInterval(_setIntervalId);
		_task = null;
	}

	@post
	public function postInject()
	{
		if (IS_INITIALIZED) {
			initializeTask();
		} else {
			init(_redis)
				.then(function(_) {
					IS_INITIALIZED = true;
					initializeTask();
				});
		}
	}

	/**
	 * Extend the time on this timer
	 * @return [description]
	 */
	public function bump(ms :Float) :Promise<Bool>
	{
		var t = time();
		t += ms;
		return evaluateLuaScript(_redis, SCRIPT_CHECK_TASK, [_taskId, _interval, t]);
	}

	function shouldRun() :Promise<Bool>
	{
		return evaluateLuaScript(_redis, SCRIPT_CHECK_TASK, [_taskId, _interval, time()]);
	}

	inline static function time() :Float
	{
		return Date.now().getTime();
	}

	inline static var PREFIX = 'distributed_task${SEP}';
	inline public static var REDIS_KEY_HASH_DISTRIBUTED_TASKS = '${PREFIX}distributed_tasks';//<TaskId, TIme>

	static var SCRIPT_CHECK_TASK = '${PREFIX}check_distribued_task';

	/* The literal Redis Lua scripts. These allow non-race condition and performant operations on the DB*/
	static var scripts :Map<String, String> = [
	SCRIPT_CHECK_TASK =>
	'
		local taskId = ARGV[1]
		local interval = tonumber(ARGV[2])
		local currentTimeString = tonumber(ARGV[3])
		local currentTime = tonumber(currentTimeString)
		if redis.call("HEXISTS", "${REDIS_KEY_HASH_DISTRIBUTED_TASKS}", taskId) == 0 then
			redis.call("HSET", "${REDIS_KEY_HASH_DISTRIBUTED_TASKS}", taskId, currentTimeString)
			return true
		else
			local prevTime = tonumber(redis.call("HGET", "${REDIS_KEY_HASH_DISTRIBUTED_TASKS}", taskId))
			if currentTime - prevTime >= interval then
				redis.call("HSET", "${REDIS_KEY_HASH_DISTRIBUTED_TASKS}", taskId, currentTimeString)
				return true
			else
				return false
			end
		end
	',
	];

	/* When we call a Lua script, use the SHA of the already uploaded script for performance */
	static var SCRIPT_SHAS :Map<String, String>;
	static var SCRIPT_SHAS_TOIDS :Map<String, String>;

	public static function evaluateLuaScript<T>(redis :RedisClient, scriptKey :String, ?args :Array<Dynamic>) :Promise<T>
	{
		return RedisLuaTools.evaluateLuaScript(redis, SCRIPT_SHAS[scriptKey], null, args, SCRIPT_SHAS_TOIDS, scripts);
	}

	public static function init(redis :RedisClient) :Promise<Bool>//You can chain this to a series of piped promises
	{
		for (key in scripts.keys()) {
			var script = scripts.get(key);
			if (script.indexOf('local SCRIPTID') == -1) {
				script = 'local SCRIPTID = "$key"\n' + script;
				scripts.set(key, script);
			}
		}
		return RedisLuaTools.initLuaScripts(redis, scripts)
			.then(function(scriptIdsToShas :Map<String, String>) {
				SCRIPT_SHAS = scriptIdsToShas;
				//This helps with debugging the lua scripts, uses the name instead of the hash
				SCRIPT_SHAS_TOIDS = new Map();
				for (key in SCRIPT_SHAS.keys()) {
					SCRIPT_SHAS_TOIDS[SCRIPT_SHAS[key]] = key;
				}
				return SCRIPT_SHAS != null;
			});
	}
}