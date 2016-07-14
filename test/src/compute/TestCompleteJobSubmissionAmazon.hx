package compute;

import promhx.Promise;

import ccc.compute.InstancePool;
import ccc.compute.InitConfigTools;
import ccc.compute.workers.WorkerProviderPkgCloud;
import ccc.storage.StorageTools;
import ccc.storage.ServiceStorage;

using promhx.PromiseTools;
using ccc.compute.InstancePool;
using ccc.compute.workers.WorkerProviderTools;
using StringTools;
using Lambda;

class TestCompleteJobSubmissionAmazon extends TestCompleteJobSubmissionBase
{
	private var _storageService :ServiceStorage;

	public function new()
	{
		super();
	}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				var config :ServiceConfiguration = InitConfigTools.ohGodGetConfigFromSomewhere();
				if(config.server.storage != null) {
					var storageConfig = config.server.storage;//StorageTools.getConfigFromServiceConfiguration(config);
					Log.info('Configuration specifies a Storage Definition of type: ${storageConfig.type}');
					_storageService = StorageTools.getStorage(storageConfig);
				}

				var workerConfig :ServiceConfigurationWorkerProviderPkgCloud = TestPkgCloudAws.getConfig(config);
				assertTrue(workerConfig != null);
				var provider = new WorkerProviderPkgCloud(workerConfig);
				_injector.injectInto(provider);
				_workerProvider = provider;
				return _workerProvider.ready;
			});
	}

	@timeout(600000) //10m
	public function testCompleteJobSubmissionAmazon()
	{
		return completeJobSubmission(_storageService, 2);
	}
}