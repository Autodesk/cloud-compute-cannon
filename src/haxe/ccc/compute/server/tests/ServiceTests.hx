package ccc.compute.server.tests;

import haxe.unit.async.PromiseTestRunner;
/**
 * Run tests via RPC or curl/HTTP.
 */
class ServiceTests
{
	@rpc({
		alias:'server-tests',
		doc:'Run all server functional tests'
	})
	public function runServerTests() :Promise<CompleteTestResult>
	{
		return TestServerAPI.runServerAPITests('localhost:$SERVER_DEFAULT_PORT');
	}

	public function new() {}
}