package ccc.lambda;

import haxe.Json;
import js.Error;
import js.npm.redis.RedisClient;

@:build(t9.redis.RedisObject.build())
class RedisLogGetter
{
	static var SCRIPT_GET_LOGS = '
		local logs = {}
		local log = redis.call("RPOP", "${RedisLoggerTools.REDIS_KEY_LOGS_LIST}")

		while log do
			table.insert(logs, log)
			log = redis.call("RPOP", "${RedisLoggerTools.REDIS_KEY_LOGS_LIST}")
		end
		return logs
	';
	@redis({lua:'${SCRIPT_GET_LOGS}'})
	public static function getLogsInternal() :Promise<Array<String>> {}
	public static function getLogs() :Promise<Array<Dynamic>>
	{
		return getLogsInternal()
			.then(function(logArray :Array<String>) {
				if (RedisLuaTools.isArrayObjectEmpty(logArray)) {
					return null;
				} else {
					return logArray.map(Json.parse).map(function(o :DynamicAccess<Dynamic>) {
						o.addLogStack(LogFieldStack.RedisTag);
						return o;
					});
				}
			});
	}
}