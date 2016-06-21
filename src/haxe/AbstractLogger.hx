abstract AbstractLogger(js.npm.Bunyan.BunyanLogger) to js.npm.Bunyan.BunyanLogger from js.npm.Bunyan.BunyanLogger
{
	inline public function new(fields :Dynamic)
	{
		this = js.npm.Bunyan.createLogger(fields);
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
		var obj :Dynamic = switch(untyped __typeof__(logThing)) {
			case 'object': logThing;
			default: {message:Std.string(logThing)};
		}
		Reflect.setField(obj, 'src', {file:pos.fileName, line:pos.lineNumber});
		// Reflect.setField(obj, 'level', Std.int(logCode / 10));
		Reflect.setField(obj, 'time', untyped __js__('new Date().toISOString()'));
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
// 			case 100: js.npm.CliColor.redBright(s);
// 			case 200: js.npm.CliColor.red(s);
// 			case 300: js.npm.CliColor.magenta(s);
// 			case 400: js.npm.CliColor.green(s);
// 			case 500: js.npm.CliColor.yellow(s);
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