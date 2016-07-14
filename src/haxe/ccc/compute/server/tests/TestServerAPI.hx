package ccc.compute.server.tests;

import js.Node;

import haxe.unit.async.PromiseTestRunner;

class TestServerAPI
{
	static function main()
	{
		var args = Sys.args();
		if (args.length == 0) {
			trace('Please give an host and optionally port as the argument, e.g. "192.168.99.100" or "192.168.99.100:9000"');
		} else {
			var host :Host = args[0].trim();
			if (host.port() == null) {
				host = new Host(host.getHostname(), new Port(SERVER_DEFAULT_PORT));
			}
			runServerAPITests(host, null);
		}
	}

	/**
	 * This executes all tests against a server with address env.CCC_ADDRESS
	 * @return [description]
	 */
	public static function runServerAPITests(targetHost :Host, injector :Injector) :Promise<CompleteTestResult>
	{
		var runner = new PromiseTestRunner();

		// runner.add(new TestRegistry(targetHost));
		if (injector != null) {
			runner.add(TestServiceStorage.create(injector));
		}

		runner.add(new TestJobs(targetHost));

		var exitOnFinish = false;
		var disableTrace = true;
		return runner.run(exitOnFinish, disableTrace);
	}
}