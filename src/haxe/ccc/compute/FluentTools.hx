package ccc.compute;

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

	static var static_emitter =
		FluentLogger.createFluentSender(null,
			{
				host: ConnectionToolsDocker.getContainerAddress('fluentd'),
				port: FLUENTD_SOURCE_PORT
			}).emit.bind(APP_NAME_COMPACT, _, _, _);
}
