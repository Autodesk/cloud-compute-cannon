package ccc;

import ccc.Constants.*;
import ccc.SharedConstants.*;

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

	static function logToRedis(redis :RedisClient, level :String, logThing :Dynamic, pos :haxe.PosInfos)
	{
		var obj :haxe.DynamicAccess<Dynamic> = switch(untyped __typeof__(logThing)) {
			case 'object': cast logThing;
			default: cast {message:Std.string(logThing)};
		}
		if (pos != null) {
			obj['src'] = {file:pos.fileName, line:pos.lineNumber, func:'${pos.className.split(".").pop()}.${pos.methodName}'};
		}
		obj.set('level', level);
		obj.set('time', Date.now().getTime());
		var logString = Json.stringify(obj);
		trace(logString);
		redis.rpush(REDIS_KEY_LOGS_LIST, Json.stringify(obj), function(err, result) {
			if (err != null) {
				trace(err);
				// try {
				// 	redis.publish(REDIS_KEY_LOGS_CHANNEL, 'logs');
				// } catch(err :Dynamic) {
				// 	//Swallow
				// }
			}
		});
		// Node.console.log(obj);
	}

	public static function debugLog(redis :RedisClient, obj :Dynamic, ?pos :haxe.PosInfos)
	{
		logToRedis(redis, REDIS_LOG_DEBUG, obj, pos);
	}

	public static function infoLog(redis :RedisClient, obj :Dynamic, ?pos :haxe.PosInfos)
	{
		logToRedis(redis, REDIS_LOG_INFO, obj, pos);
	}

	public static function errorLog(redis :RedisClient, obj :Dynamic, ?pos :haxe.PosInfos)
	{
		logToRedis(redis, REDIS_LOG_ERROR, obj, pos);
	}

	public static function errorEventLog(redis :RedisClient, err :Error, ?message :String, ?pos :haxe.PosInfos)
	{
		var errObj = {
			errorJson: try{Json.stringify(err);} catch(e :Dynamic) {null;},
			stack: try{err.stack;} catch(e :Dynamic) {null;},
			errorMessage: try{err.message;} catch(e :Dynamic) {null;},
			message: message
		};
		logToRedis(redis, REDIS_LOG_ERROR, errObj, pos);
	}
}