package ccc.compute.server;

import haxe.extern.EitherType;

import js.npm.fluentlogger.FluentLogger;

typedef LogObj = {
	var message :Dynamic;
}

class FluentTools
{
	public static function createEmitter()
	{
		return function(obj :Dynamic, ?cb :Void->Void) :Void {
			var msg :LogObj = switch(untyped __typeof__(obj)) {
				case 'object': obj;
				default: {message:Std.string(obj)};
			}
			if (Reflect.hasField(msg, 'time')) {
				Reflect.setField(msg, '@timestamp', Reflect.field(msg, 'time').toISOString());
			}
			if (!Reflect.hasField(msg, '@timestamp')) {
				Reflect.setField(msg, '@timestamp', untyped __js__('new Date().toISOString()'));
			}
			Reflect.deleteField(msg, 'time');
			static_emitter(msg, null, cb);
		}
	}

	public static function logToFluent(obj :Dynamic, ?cb :Void->Void)
	{
		createEmitter()(obj, cb);
	}

	private static function readFluentPort() :Int
	{
		var env = js.Node.process.env;
		var fluentPort :Int = Reflect.hasField(env, 'FLUENT_PORT') ? Std.int(Reflect.field(env, 'FLUENT_PORT')) : FLUENTD_SOURCE_PORT;	

		return fluentPort;
	}

	static var FLUENT_PORT = readFluentPort();

	static var static_emitter =
		FluentLogger.createFluentSender(null,
			{
				host: ConnectionToolsDocker.getContainerAddress('fluentd'),
				port: FLUENT_PORT
			}).emit.bind(APP_NAME_COMPACT, _, _, _);
}
