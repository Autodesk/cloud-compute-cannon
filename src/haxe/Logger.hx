import js.npm.bunyan.Bunyan;

/**
 * This is the root logger.
 */
class Logger
{
	public static var log :AbstractLogger;

	inline public static function trace(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		log.trace(msg, pos);
	}

	inline public static function debug(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		log.debug(msg, pos);
	}

	inline public static function info(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		log.info(msg, pos);
	}

	inline public static function warn(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		log.warn(msg, pos);
	}

	inline public static function error(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		log.error(msg, pos);
	}

	inline public static function critical(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		log.critical(msg, pos);
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
// 		var jobColorFilter : js.node.stream.Transform<Dynamic> = untyped __js__("new require('stream').Transform({objectMode:true})");
// 		var transform = function(chunk:js.node.Buffer, encoding:String, callback:js.Error->haxe.extern.EitherType<String,js.node.Buffer>->Void):Void {
// 			var logObj :Dynamic = cast chunk;
// 			var s;
// 			try {
// 				s = haxe.Json.stringify(logObj);
// 			} catch (err :Dynamic) {
// 				Sys.println(err);
// 				s = Std.string(chunk);
// 			}
// // #if debug
// // 			if (s.indexOf('privateKey') > -1) {
// // 				Sys.println(haxe.Json.stringify({error:'Found privateKey in log statement', statement:s}));
// // 			}
// // #end

// 			//Colorize job specific log messages for easier debugging
// 			if (Reflect.hasField(logObj, 'jobid')) {
// 				var color = util.CliColors.colorFromString(Reflect.field(logObj, 'jobid'));
// 				var f :String->String = Reflect.field(js.npm.clicolor.CliColor, color);
// 				s = f(s);
// 			}
// 			s += '\n';
// 			callback(null, s);
// 		}
// 		Reflect.setField(jobColorFilter, '_transform', transform);
// 		jobColorFilter.pipe(js.Node.process.stdout);
		log = new AbstractLogger(
		{
			name: ccc.compute.Constants.SERVER_CONTAINER_TAG_SERVER,
			level: Bunyan.DEBUG,
			// streams: [
			// 	{
			// 		level: Bunyan.DEBUG,
			// 		// type: 'raw',// use 'raw' to get raw log record objects 
			// 		// stream: jobColorFilter
			// 	}
			// ],
			src: false
		});
	}
}