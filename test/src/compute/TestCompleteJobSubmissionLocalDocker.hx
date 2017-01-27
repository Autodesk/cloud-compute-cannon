package compute;

class TestCompleteJobSubmissionLocalDocker extends TestCompleteJobSubmissionBase
{
	public function new()
	{
		super();
	}

	override public function setup() :Null<Promise<Bool>>
	{
		var config :ServiceConfigurationWorkerProvider = {
			type: ServiceWorkerProviderType.boot2docker,
			maxWorkers: 1,
			minWorkers: 0,
			priority: 1,
			billingIncrement: 0
		};
		_workerProvider = new WorkerProviderBoot2Docker(config);
		return super.setup()
			.pipe(function(_) {
				_injector.injectInto(_workerProvider);
				return _workerProvider.ready;
			});
	}

	@timeout(600000) //10m
	public function testCompleteJobSubmissionLocalDocker()
	{
		return completeJobSubmission(1);
	}
}