package ccc.compute.shared;

abstract AbstractLogger(js.npm.bunyan.Bunyan.BunyanLogger) to js.npm.bunyan.Bunyan.BunyanLogger from js.npm.bunyan.Bunyan.BunyanLogger
{
	inline public function new(fields :Dynamic)
	{
		this = js.npm.bunyan.Bunyan.createLogger(fields);
	}

	inline public function child(fields :Dynamic) :AbstractLogger
	{
		var newChild = this.child(fields);
		newChild.level(this.level());
		return newChild;
	}

	static function isObject(v :Dynamic) :Bool
	{
		return untyped __js__('(!!v) && (v.constructor === Object)');
	}

	static function processLogMessage(logThing :Dynamic, pos :haxe.PosInfos)
	{
		var obj :haxe.DynamicAccess<Dynamic> = switch(untyped __typeof__(logThing)) {
			case 'object': cast Reflect.copy(logThing);
			default: cast {message:Std.string(logThing)};
		}
		obj['src'] = {file:pos.fileName, line:pos.lineNumber, func:'${pos.className.split(".").pop()}.${pos.methodName}'};
		//Ensure errors are strings, not objects, for eventual consumption by Elasticsearch
		if (obj.exists('error') && obj['error'] != null) {
			switch(untyped __typeof__(obj['error'])) {
				case 'string': //Good
				default:
					try {
						var e = obj['error'];
						obj['error'] = e.stack != null ? e.stack : e + '';
					} catch (err :Dynamic) {
						//Swallow
					}
			}
		}
		return obj;
	}

	inline public function trace(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (Logger.GLOBAL_LOG_LEVEL <= 10) {
			this.trace(processLogMessage(msg, pos));
		}
	}

	inline public function debug(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (Logger.GLOBAL_LOG_LEVEL <= 20) {
			this.debug(processLogMessage(msg, pos));
		}
	}

	inline public function info(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (Logger.GLOBAL_LOG_LEVEL <= 30) {
			this.info(processLogMessage(msg, pos));
		}
	}

	inline public function warn(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (Logger.GLOBAL_LOG_LEVEL <= 40) {
			this.warn(processLogMessage(msg, pos));
		}
	}

	inline public function error(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (Logger.GLOBAL_LOG_LEVEL <= 50) {
			this.error(processLogMessage(msg, pos));
		}
	}

	inline public function critical(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		if (Logger.GLOBAL_LOG_LEVEL <= 60) {
			this.fatal(processLogMessage(msg, pos));
		}
	}

	inline public function level(?newLevel :Null<Int>) :Int
	{
		if (newLevel != null) {
			untyped this._level = newLevel;
			untyped this.streams[0].level = newLevel;
		} else {

		}
		return untyped this._level;
	}
}