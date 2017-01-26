package compute;

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
				if(config.storage != null) {
					var storageConfig = config.storage;//StorageTools.getConfigFromServiceConfiguration(config);
					Log.info('Configuration specifies a Storage Definition of type: ${storageConfig.type}');
					_storageService = StorageTools.getStorage(storageConfig);
				}

				var workerConfig :ServiceConfigurationWorkerProvider = TestPkgCloudAws.getConfig(config);
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