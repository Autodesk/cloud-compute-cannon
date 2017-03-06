package ccc.compute.server;

class ServerConfigTools
{
	public static function getConfig(injector :Injector) :Promise<ServiceConfiguration>
	{
		var config :ServiceConfiguration = injector.getValue('ccc.compute.shared.ServiceConfiguration');
		return Promise.promise(config);
	}

	public static function getProviderConfig(injector :Injector) :Promise<ServiceConfigurationWorkerProvider>
	{
		var config :ServiceConfigurationWorkerProvider = injector.getValue('ccc.compute.shared.ServiceConfigurationWorkerProvider');
		return Promise.promise(config);
	}
}