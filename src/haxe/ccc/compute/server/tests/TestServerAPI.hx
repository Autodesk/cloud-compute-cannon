package ccc.compute.server.tests;

import js.Node;

import haxe.unit.async.PromiseTestRunner;

class TestServerAPI
{
	static function main()
	{
		var args = Sys.args;
		trace('args=${args}');
		// runServerAPITests()
	}

	/**
	 * This executes all tests against a server with address env.CCC_ADDRESS
	 * @return [description]
	 */
	public static function runServerAPITests(targetHost :Host) :Promise<Bool>
	{
		var runner = new PromiseTestRunner();

		//Run the unit tests. These do not require any external dependencies
		// runner.add(new utils.TestMiscUnit());
		// runner.add(new utils.TestPromiseQueue());
		// runner.add(new utils.TestStreams());
		// runner.add(new storage.TestStorageRestAPI());
		// runner.add(new storage.TestStorageLocal());
		// runner.add(new compute.TestRedisMock());
		// // if (isInternet) {
		// // 	runner.add(new storage.TestStorageSftp());
		// // }


		// // if (isRedis) {
		// // 	// These require a local redis db
		// runner.add(new compute.TestAutoscaling());
		// runner.add(new compute.TestRedis());

		runner.add(new TestRegistry(targetHost));
		

		// 	//These require access to a local docker server
		// 	if (isDockerProvider) {
		// 		runner.add(new compute.TestScheduler());
		// 		runner.add(new compute.TestJobStates());
		// 		runner.add(new compute.TestInstancePool());
		// 		runner.add(new compute.TestComputeQueue());
		// 		runner.add(new compute.TestScalingMock());

		// 		runner.add(new compute.TestCompleteJobSubmissionLocalDocker());
		// 		runner.add(new compute.TestRestartAfterCrashLocalDocker());
		// 		runner.add(new compute.TestDockerCompute());
		// 		runner.add(new compute.TestServiceBatchCompute());
		// 	}

		// 	// runner.add(new compute.TestCLIRemoteServerInstallation());
		// 	// runner.add(new compute.TestJobStates());
		// 	//CLI
		// 	// runner.add(new compute.TestCLISansServer());
		// 	// runner.add(new compute.TestCLI());
		// }

		// if (isVagrant && isRedis) {
		// 	runner.add(new compute.TestVagrant());
		// 	runner.add(new compute.TestScalingVagrant());
		// 	runner.add(new compute.TestCompleteJobSubmissionVagrant());
		// 	runner.add(new compute.TestRestartAfterCrashVagrant());
		// }

		// if (isAws) {
		// 	// runner.add(new compute.TestPkgCloudAws());
		// 	runner.add(new compute.TestScalingAmazon());
		// 	// runner.add(new compute.TestCompleteJobSubmissionAmazon());
		// 	// runner.add(new compute.TestRestartAfterCrashAWS());
		// }

		return runner.run(false);
	}
}