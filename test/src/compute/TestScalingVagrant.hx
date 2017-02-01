package compute;

class TestScalingVagrant extends TestScalingBase
{
	public function new() super();

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				return WorkerProviderVagrant.destroyAllVagrantMachines();
			})
			.pipe(function(_) {
				_workerProvider = new WorkerProviderVagrant();
				_injector.injectInto(_workerProvider);
				return _workerProvider.ready;
			});
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		return super.tearDown()
			.pipe(function(_) {
				return WorkerProviderVagrant.destroyAllVagrantMachines();
			});
	}

	@timeout(600000)//10 minutes
	public function testScalingVagrant()
	{
		return baseTestScalingMachines();
	}
}