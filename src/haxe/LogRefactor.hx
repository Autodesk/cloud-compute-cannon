// abstract AbstractLogger(js.npm.bunyan.Bunyan.Logger) to js.npm.bunyan.Bunyan.Logger from js.npm.bunyan.Bunyan.Logger
// {
// 	inline public function new(fields :Dynamic)
// 	{
// 		this = js.npm.bunyan.Bunyan.createLogger(fields);
// 	}

// 	inline public function child(fields :Dynamic) :AbstractLogger
// 	{
// 		return this.child(fields);
// 	}

// 	static function isObject(v :Dynamic) :Bool
// 	{
// 		return untyped __js__('(!!v) && (v.constructor === Object)');
// 	}

// 	static function processLogMessage(msg :Dynamic, logCode :Int, pos :haxe.PosInfos)
// 	{
// 		var obj :Dynamic = switch(untyped __typeof__(msg)) {
// 			case 'object': msg;
// 			default: {m:Std.string(msg)};
// 		}
// 		Reflect.setField(obj, 'src', {file:pos.fileName, line:pos.lineNumber});
// 		Reflect.setField(obj, 'level', Std.int(logCode / 10));
// 		return obj;
// 	}

// 	inline public function trace(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		this.info(processLogMessage(msg, 400, pos));
// 	}

// 	inline public function debug(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		this.info(processLogMessage(msg, 400, pos));
// 	}

// 	inline public function info(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		this.info(processLogMessage(msg, 400, pos));
// 	}

// 	inline public function warn(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		this.warn(processLogMessage(msg, 300, pos));
// 	}

// 	inline public function error(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		this.error(processLogMessage(msg, 200, pos));
// 	}

// 	inline public function critical(msg :Dynamic, ?pos :haxe.PosInfos) :Void
// 	{
// 		this.fatal(processLogMessage(msg, 100, pos));
// 	}
// }

@:enum
abstract LogLevel(Int) {
  var Critical = 10;
  var Error = 20;
  var Warn = 30;
  var Info = 40;
  var Debug = 50;
  var Trace = 60;
}

typedef LogWrite=Dynamic->Void;

typedef LoggerDef = {
	var debug :LogWrite;
	var info :LogWrite;
	var warn :LogWrite;
	var error :LogWrite;
	var critical :LogWrite;
	function child (fields :Dynamic) :LoggerDef;
}

class LogTools
{
	inline public static function isObject(v :Dynamic) :Bool
	{
		return untyped __js__('(!!v) && (v.constructor === Object)');
	}

	public static function colorizeLogMessage(s :String, level :LogLevel)
	{
		return switch(level) {
			case Critical: js.npm.clicolor.CliColor.redBright(s);
			case Error: js.npm.clicolor.CliColor.red(s);
			case Warn: js.npm.clicolor.CliColor.magenta(s);
			case Info: js.npm.clicolor.CliColor.green(s);
			case Debug: js.npm.clicolor.CliColor.yellow(s);
			case Trace: s;
			default:s;
		}
	}

	public static function addPosInfoToString(msg :Dynamic, pos :haxe.PosInfos) :String
	{
		return '${pos.fileName}:${pos.lineNumber} ${haxe.Json.stringify(msg)}';
	}
}


abstract AbstractLogger(LoggerDef)
{
	var internalLogger :LoggerDef;
	inline public function new(fields :Dynamic)
	{
		this = fields;
	}

	inline public function child(fields :Dynamic) :AbstractLogger
	{
		for (f in Reflect.fields(this)) {
			Reflect.setField(fields, f, Reflect.field(this, f));
		}
		return fields;
	}

	static function processLogMessage(msg :Dynamic, logCode :Int, pos :haxe.PosInfos)
	{
		// var obj :Dynamic = switch(untyped __typeof__(msg)) {
		// 	case 'object': msg;
		// 	default: {m:Std.string(msg)};
		// }
		// Reflect.setField(obj, 'src', {file:pos.fileName, line:pos.lineNumber});
		// Reflect.setField(obj, 'level', Std.int(logCode / 10));
		// return obj;

		var s = '${pos.fileName}:${pos.lineNumber} ${haxe.Json.stringify(msg)}';
		return switch(logCode) {
			case 100: js.npm.clicolor.CliColor.redBright(s);
			case 200: js.npm.clicolor.CliColor.red(s);
			case 300: js.npm.clicolor.CliColor.magenta(s);
			case 400: js.npm.clicolor.CliColor.green(s);
			case 500: js.npm.clicolor.CliColor.yellow(s);
			case 600: s;
			default:s;
		}
	}

	inline public function trace(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		js.Node.console.log(processLogMessage(msg, 600, pos));
	}

	inline public function debug(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		js.Node.console.log(processLogMessage(msg, 500, pos));
	}

	inline public function info(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		js.Node.console.log(processLogMessage(msg, 400, pos));
	}

	inline public function warn(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		js.Node.console.log(processLogMessage(msg, 300, pos));
	}

	inline public function error(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		js.Node.console.log(processLogMessage(msg, 200, pos));
	}

	inline public function critical(msg :Dynamic, ?pos :haxe.PosInfos) :Void
	{
		js.Node.console.log(processLogMessage(msg, 100, pos));
	}
}

class LoggerNodeConsole
{
	var fields :Dynamic;

	public function new(?fields :Dynamic)
	{
		this.fields = fields;
	}

	public function child(fields :Dynamic)
	{
		if (this.fields == null) {
			return new LoggerNodeConsole(fields);
		} else {
			var copy = Reflect.copy(fields);
			for (f in Reflect.fields(this.fields)) {
				Reflect.setField(copy, f, Reflect.field(this.fields, f));
			}
			return new LoggerNodeConsole(copy);
		}
	}

	inline public function trace(msg :Dynamic) :Void
	{
		js.Node.console.log(msg);
	}

	inline public function debug(msg :Dynamic) :Void
	{
		js.Node.console.log(msg);
	}

	inline public function info(msg :Dynamic) :Void
	{
		js.Node.console.log(msg);
	}

	inline public function warn(msg :Dynamic) :Void
	{
		js.Node.console.log(msg);
	}

	inline public function error(msg :Dynamic) :Void
	{
		js.Node.console.log(msg);
	}

	inline public function critical(msg :Dynamic) :Void
	{
		js.Node.console.log(msg);
	}
}

class LoggerBunyan
{
	public var bunyan :js.npm.bunyan.Bunyan.BunyanLogger;

	public function new(?fields :Dynamic)
	{
		this.bunyan = js.npm.bunyan.Bunyan.createLogger(fields);
	}

	public function child(fields :Dynamic)
	{
		var childOf = new LoggerBunyan();
		childOf.bunyan = this.bunyan.child(fields);
		return childOf;
	}

	inline public function trace(msg :Dynamic) :Void
	{
		bunyan.trace(msg);
	}

	inline public function debug(msg :Dynamic) :Void
	{
		bunyan.debug(msg);
	}

	inline public function info(msg :Dynamic) :Void
	{
		bunyan.info(msg);
	}

	inline public function warn(msg :Dynamic) :Void
	{
		bunyan.warn(msg);
	}

	inline public function error(msg :Dynamic) :Void
	{
		bunyan.error(msg);
	}

	inline public function critical(msg :Dynamic) :Void
	{
		bunyan.critical(msg);
	}
}