package compute;

import ccc.compute.ConnectionToolsRegistry;

import promhx.Promise;

import util.DockerRegistryTools;

class TestRegistryBase extends TestComputeBase
{
	public function new() {}

	public function testImageOperations()
	{
		var host = ConnectionToolsRegistry.getRegistryAddress();
		trace('host=${host}');
		return DockerRegistryTools.getRegistryImagesAndTags(host)
			.pipe(function(imagesAndTags) {
				trace('imagesAndTags=${imagesAndTags}');
				return Promise.promise(true);
			});
	}
}