package ccc.compute.server.scaling;

class CloudTools
{
	public static function getCloudProviderFromConfig(config :ServiceConfigurationWorkerProvider) :ICloudProvider
	{
		var injector = new Injector();
		injector.map(AbstractLogger).toValue(Logger.log);

		var cloudProvider :ICloudProvider = null;
		switch(config.type) {
			case boot2docker:
				cloudProvider = new ccc.compute.server.scaling.docker.CloudProviderDocker();
			case pkgcloud:
				cloudProvider = new ccc.compute.server.scaling.aws.CloudProviderAws();
			default:
				throw 'Unhandled provider type=${config.type}';
		}
		injector.injectInto(cloudProvider);

		return cloudProvider;
	}
}