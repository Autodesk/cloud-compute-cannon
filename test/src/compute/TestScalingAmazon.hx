package compute;

class TestScalingAmazon extends TestScalingBase
{
	public function new() super();

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				var config = TestPkgCloudAws.getConfig();
				var provider = new WorkerProviderPkgCloud(config);
				_injector.injectInto(provider);
				_workerProvider = provider;
				return _workerProvider.ready;
			});
	}

	@timeout(1200000)
	public function testScalingAmazon()
	{
		return baseTestScalingMachines();
	}
}