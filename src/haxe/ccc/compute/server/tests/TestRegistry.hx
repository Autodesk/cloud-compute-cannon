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
	 */
	public function testRegistryEmpty() :Promise<Bool>
	{
		var registryHost = ConnectionToolsRegistry.getRegistryAddress();
		return DockerRegistryTools.getRegistryImagesAndTags(registryHost)
			.then(function(images) {
				var fields = Reflect.fields(images);
				assertEquals(fields.length, 0);
				return true;
			});
	}

	public function new() {}
}