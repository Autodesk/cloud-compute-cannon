import haxe.Json;
import js.Error;
import js.npm.redis.RedisClient;

class RedisLoggerTools
{
	inline static var PREFIX = '${CCC_PREFIX}logs${SEP}';

	inline public static var REDIS_KEY_LOGS_LIST = '${PREFIX}list';
	inline public static var REDIS_KEY_LOGS_CHANNEL = '${PREFIX}channel';

	inline public static var REDIS_LOG_DEBUG = 'debug';
	inline public static var REDIS_LOG_INFO = 'info';
	inline public static var REDIS_LOG_WARN = 'warn';
	inline public static var REDIS_LOG_ERROR = 'error';
	/**
	 * Expects in lua:
	 *    logMessage
	 */
	public static var SNIPPET_REDIS_LOG = '
		local logMessageString = cjson.encode(logMessage)
		redis.log(redis.LOG_NOTICE, logMessageString)
		redis.call("RPUSH", "${REDIS_KEY_LOGS_LIST}", logMessageString)
		redis.call("PUBLISH", "${REDIS_KEY_LOGS_LIST}", logMessageString)
	';

	static function logToRedis(redis :RedisClient, level :String, logThing :Dynamic)
	{
		var obj :haxe.DynamicAccess<Dynamic> = switch(untyped __typeof__(logThing)) {
			case 'object': cast logThing;
			default: cast {message:Std.string(logThing)};
		}
		obj.set('level', level);
		obj.set('time', Date.now().getTime());
		var logString = Json.stringify(obj);
		trace(logString);
		redis.rpush(REDIS_KEY_LOGS_LIST, Json.stringify(obj), function(err, result) {
			redis.publish(REDIS_KEY_LOGS_CHANNEL, 'logs');
		});
		// Node.console.log(obj);
	}

	public static function debugLog(redis :RedisClient, obj :Dynamic)
	{
		logToRedis(redis, REDIS_LOG_DEBUG, obj);
	}

	public static function infoLog(redis :RedisClient, obj :Dynamic)
	{
		logToRedis(redis, REDIS_LOG_INFO, obj);
	}

	public static function errorLog(redis :RedisClient, obj :Dynamic)
	{
		logToRedis(redis, REDIS_LOG_ERROR, obj);
	}

	public static function errorEventLog(redis :RedisClient, err :Error, ?message :String)
	{
		var errObj = {
			errorJson: try{Json.stringify(err);} catch(e :Dynamic) {null;},
			stack: try{err.stack;} catch(e :Dynamic) {null;},
			errorMessage: try{err.message;} catch(e :Dynamic) {null;},
			message: message
		};
		logToRedis(redis, REDIS_LOG_ERROR, errObj);
	}
}