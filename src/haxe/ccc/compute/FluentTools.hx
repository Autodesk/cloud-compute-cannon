package ccc.compute;


import js.npm.FluentLogger;

class FluentTools
{
	public static function logToFluent(obj :Dynamic)
	{
		//TODO: change the 'tag'
		var msg :Dynamic = switch(untyped __typeof__(obj)) {
			case 'object': obj;
			default: {message:Std.string(obj)};
		}
		Reflect.setField(msg, 'time', untyped __js__('new Date().toISOString()'));
		emitter.emit('tag', obj, Date.now().getTime());
	}

	static var emitter :FluentLogger = FluentLogger.createFluentSender(APP_NAME_COMPACT,
		{
			host: ConnectionToolsDocker.getContainerAddress('fluentd')
		});
}
