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
		obj['src'] = {file:pos.fileName, line:pos.lineNumber};
		obj['time'] = untyped __js__('new Date().toISOString()');
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
		this.info(processLogMessage(msg, pos));
	}

	inline public function debug(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		this.info(processLogMessage(msg, pos));
	}

	inline public function info(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		this.info(processLogMessage(msg, pos));
	}

	inline public function warn(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		this.warn(processLogMessage(msg, pos));
	}

	inline public function error(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		this.error(processLogMessage(msg, pos));
	}

	inline public function critical(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		this.fatal(processLogMessage(msg, pos));
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

// abstract AbstractLogger({})
// {
// 	inline public function new(fields :Dynamic)
// 	{
// 		this = fields;
// 	}

// 	inline public function child(fields :Dynamic) :AbstractLogger
// 	{
// 		for (f in Reflect.fields(this)) {
// 			Reflect.setField(fields, f, Reflect.field(this, f));
// 		}
// 		return fields;
// 	}

// 	static function isObject(v :Dynamic) :Bool
// 	{
// 		return untyped __js__('(!!v) && (v.constructor === Object)');
// 	}

// 	static function processLogMessage(msg :Dynamic, logCode :Int, pos :haxe.PosInfos)
// 	{
// 		// var obj :Dynamic = switch(untyped __typeof__(msg)) {
// 		// 	case 'object': msg;
// 		// 	default: {m:Std.string(msg)};
// 		// }
// 		// Reflect.setField(obj, 'src', {file:pos.fileName, line:pos.lineNumber});
// 		// Reflect.setField(obj, 'level', Std.int(logCode / 10));
// 		// return obj;

// 		var s = '${pos.fileName}:${pos.lineNumber} ${haxe.Json.stringify(msg)}';
// 		return switch(logCode) {
// 			case 100: js.npm.clicolor.CliColor.redBright(s);
// 			case 200: js.npm.clicolor.CliColor.red(s);
// 			case 300: js.npm.clicolor.CliColor.magenta(s);
// 			case 400: js.npm.clicolor.CliColor.green(s);
// 			case 500: js.npm.clicolor.CliColor.yellow(s);
// 			case 600: s;
// 			default:s;
// 		}
// 	}

// 	inline public function trace(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		js.Node.console.log(processLogMessage(msg, 600, pos));
// 	}

// 	inline public function debug(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		js.Node.console.log(processLogMessage(msg, 500, pos));
// 	}

// 	inline public function info(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		js.Node.console.log(processLogMessage(msg, 400, pos));
// 	}

// 	inline public function warn(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		js.Node.console.log(processLogMessage(msg, 300, pos));
// 	}

// 	inline public function error(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		js.Node.console.log(processLogMessage(msg, 200, pos));
// 	}

// 	inline public function critical(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		js.Node.console.log(processLogMessage(msg, 100, pos));
// 	}
// }