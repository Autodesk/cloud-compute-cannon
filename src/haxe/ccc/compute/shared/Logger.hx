package ccc.compute.shared;

import js.npm.bunyan.Bunyan;

/**
 * This is the root logger.
 */
class Logger
{
	public static var GLOBAL_LOG_LEVEL :Int = switch(ccc.compute.shared.ServerConfig.LOG_LEVEL) {
		case 'trace': Bunyan.TRACE;
		case 'debug': Bunyan.DEBUG;
		case 'info': Bunyan.INFO;
		case 'warn': Bunyan.WARN;
		case 'error': Bunyan.ERROR;
		case 'critical': Bunyan.FATAL;
		default: Bunyan.INFO;
	};

	public static var log :AbstractLogger;

	inline public static function trace(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= Bunyan.TRACE) {
			log.trace(msg, pos);
		}
	}

	inline public static function debug(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= Bunyan.DEBUG) {
			log.debug(msg, pos);
		}
	}

	inline public static function info(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= Bunyan.INFO) {
			log.info(msg, pos);
		}
	}

	inline public static function warn(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= Bunyan.WARN) {
			log.warn(msg, pos);
		}
	}

	inline public static function error(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= Bunyan.ERROR) {
			log.error(msg, pos);
		}
	}

	inline public static function critical(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= Bunyan.FATAL) {
			log.critical(msg, pos);
		}
	}

	inline public static function child(fields :Dynamic) :AbstractLogger
	{
		return log.child(fields);
	}

	inline public static function ensureLog(logger :AbstractLogger, ?fields :Dynamic) :AbstractLogger
	{
		var parent = logger != null ? logger : log;
		var child = parent;
		if (fields != null) {
			child = parent.child(fields);
		}
		untyped child._level = parent._level;
		untyped child.streams[0].level = parent._level;
		return child;
	}

	inline static function __init__()
	{
		var level = js.Node.process.env.get('LOG_LEVEL');
		level = level != null ? level : 'info';
		level = 'debug';
 		var streams :Array<Dynamic> = [
			{
				level: level,
				stream: js.Node.require('bunyan-format')({outputMode:'short'})
			}
		];

		if (ServerConfig.FLUENT_HOST != null) {
#if (!clientjs)
			var fluentLogger = {write:ccc.compute.server.logs.FluentTools.createEmitter()};
			streams.push({
				level: level,
				type: 'raw',// use 'raw' to get raw log record objects
				stream: fluentLogger
			});
#end
		}

		log = new AbstractLogger(
		{
			name: ccc.compute.shared.Constants.SERVER_CONTAINER_TAG_SERVER,
			level: level,
			streams: streams,
			src: false
		});
	}
}