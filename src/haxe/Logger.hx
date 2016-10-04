import js.npm.bunyan.Bunyan;

/**
 * This is the root logger.
 */
class Logger
{
	public static var GLOBAL_LOG_LEVEL :Int = 30;
	public static var IS_FLUENT = true;

	public static var log :AbstractLogger;

	inline public static function trace(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= 10) {
			log.trace(msg, pos);
		}
	}

	inline public static function debug(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= 20) {
			log.debug(msg, pos);
		}
	}

	inline public static function info(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= 30) {
			log.info(msg, pos);
		}
	}

	inline public static function warn(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= 40) {
			log.warn(msg, pos);
		}
	}

	inline public static function error(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= 50) {
			log.error(msg, pos);
		}
	}

	inline public static function critical(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (GLOBAL_LOG_LEVEL <= 60) {
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
 		var streams :Array<Dynamic> = [
			{
				level: Bunyan.TRACE,
				stream: js.Node.process.stdout
			}
		];

		if (ccc.compute.ConnectionToolsDocker.isInsideContainer()) {
			var fluentLogger = {write:ccc.compute.FluentTools.createEmitter()};
			streams.push({
				level: Bunyan.TRACE,
				type: 'raw',// use 'raw' to get raw log record objects
				stream: fluentLogger
			});
		} else {
			IS_FLUENT = false;
		}

		log = new AbstractLogger(
		{
			name: ccc.compute.Constants.SERVER_CONTAINER_TAG_SERVER,
			level: Bunyan.TRACE,
			streams: streams,
			src: false
		});
	}
}