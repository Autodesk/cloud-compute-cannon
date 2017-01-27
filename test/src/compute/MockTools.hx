package compute;

import ccc.compute.server.Stack;

class MockTools
{
	/**
	 * This assumes that the injector has a redis client
	 */
	public static function createMockStack(injector :Injector, ?providerConfig :ServiceConfigurationWorkerProvider) :Promise<Stack>
	{
		var workerManager = new MockWorkerManager();
		var workerProvider = new MockWorkerProvider(providerConfig);
		var jobsManager = new MockJobs();

		injector.map(WorkerManager).toValue(workerManager);
		injector.map(WorkerProvider).toValue(workerProvider);
		injector.map(Jobs).toValue(jobsManager);

		injector.injectInto(workerManager);
		injector.injectInto(workerProvider);
		injector.injectInto(jobsManager);

		return workerProvider.ready
			.then(function(_) {
				var jobStackDef :StackDef = {manager:workerManager,provider:workerProvider,jobs:jobsManager};
				var jobStack :Stack = jobStackDef;
				return jobStack;
			});
	}
}
