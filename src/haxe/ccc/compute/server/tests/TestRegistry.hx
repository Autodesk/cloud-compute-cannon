package ccc.compute.server.tests;

import ccc.compute.ConnectionToolsRegistry;

import util.DockerRegistryTools;

class TestRegistry extends ServerAPITestBase
{
	/**
	 * After the tests runs the setup, everything
	 * should be clear and empty, including the registry.
	 * Without the registry being empty, other tests
	 * may not work.
	 * This may be complete bullshit.
	 */
	public function DISABLED_UNTIL_THIS_MAKES_SENSE_testRegistryEmpty() :Promise<Bool>
	{
		var registryHost = new Host(_serverHost.getHostname(), new Port(REGISTRY_DEFAULT_PORT));
		return DockerRegistryTools.getRegistryImagesAndTags(registryHost)
			.then(function(images) {
				var fields = Reflect.fields(images);
				assertEquals(fields.length, 0);
				return true;
			});
	}

	public function new(targetHost :Host)
	{
		super(targetHost);
	}
}