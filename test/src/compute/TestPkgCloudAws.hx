 package compute;

import js.Node;
import js.npm.PkgCloud;
import js.npm.RedisClient;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.PromiseTools;

import ccc.compute.InitConfigTools;
import ccc.compute.Definitions;
import ccc.compute.workers.WorkerProviderPkgCloud;

using StringTools;
using Lambda;
using promhx.PromiseTools;

class TestPkgCloudAws extends TestComputeBase
{
	public static function getConfig(?config :ServiceConfiguration) :ServiceConfigurationWorkerProviderPkgCloud
	{
		if(config == null) {
			config = InitConfigTools.ohGodGetConfigFromSomewhere();
		}
		Log.debug('TestPkgCloudAws.getConfig config=$config');

		if (config != null) {
			return cast config.providers.find(function(p) {
				var awsCredentials :ServiceConfigurationWorkerProviderPkgCloud = cast p;
				return awsCredentials != null && awsCredentials.credentials != null && awsCredentials.credentials.provider == ProviderType.amazon;
			});
		} else {
			return null;
		}
	}

	public function new() {}

	@timeout(20000)//This can take a long time
	public function testAws()
	{
		// Log.debug('TestPkgCloudAws.testAws');
		var pkg = Node.require('pkgcloud');
		var redis = _redis;
		// Log.debug('TestPkgCloudAws.testAws redis=${redis != null}');
		Assert.notNull(redis);
		var injector = new minject.Injector();
		injector.map(RedisClient).toValue(redis);
		// Log.debug('TestPkgCloudAws.testAws getConfig()=${getConfig()}');
		var service = new WorkerProviderPkgCloud(getConfig());
		_workerProvider = service;//It gets cleaned up in tearDown this way
		injector.injectInto(service);

		return Promise.promise(true)
			.pipe(function(_) {
				return service.compute.getServers();
			})
			// .traceJson()
			.then(function(servers) {
				// Log.debug('TestPkgCloudAws.testAws servers=${servers}');
				return servers.filter(function(s) return s.status == PkgCloudComputeStatus.running);
			})
			// .traceJson()
			.then(function(servers) {
				// Log.debug('TestPkgCloudAws.testAws servers=${servers}');
				return assertTrue(servers.length > 0);
			})
			// .then(function(server) {
			// 	trace('server=${server}');
			// 	// for (f in Reflect.fields(server)) {
			// 	// 	trace('f=${f}');
			// 	// }
			// 	// trace(Reflect.field(server, 'client'));
			// 	// return servers.find(function(s) return s.id == 'i-8b36b839');
			// 	return server;
			// })
			// .traceJson()
			.thenTrue();
	}
}