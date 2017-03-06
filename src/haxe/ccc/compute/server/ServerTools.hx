package ccc.compute.server;

import minject.Injector;

class ServerTools
{
	public static function initServerMetadata(injector :Injector) :MachineId
	{
		return RequestPromises.get('http://169.254.169.254/latest/meta-data/instance-id')
			.pipe(function(instanceId) {
				instanceId = instanceId.trim();
				injector.map(String, SERVER_ID).toValue(instanceId);
				return 
			})
			.errorPipe(function(ignored) {
				//Local docker container setup
			});

	}

	public static function getServerId(injector :Injector) :MachineId
	{
		return injector.getValue(String, SERVER_ID);
	}

	public static function getServerHostPublic(injector :Injector) :String
	{
		return injector.getValue(String, SERVER_HOST_PUBLIC);
	}

	public static function getServerHostPrivate(injector :Injector) :String
	{
		return injector.getValue(String, SERVER_HOST_PRIVATE);
	}

	static var SERVER_ID = "SERVER_ID";
	static var SERVER_HOST_PUBLIC = "SERVER_HOST_PUBLIC";
	static var SERVER_HOST_PRIVATE = "SERVER_HOST_PRIVATE";
}