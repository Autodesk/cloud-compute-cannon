package ccc.compute.test.tests;

import ccc.compute.server.services.ServiceMonitorRequest;

using promhx.PromiseTools;

class TestMonitor
	extends haxe.unit.async.PromiseTest
{
	@timeout(2000)
	public function testCCCServerReachable() :Promise<Bool>
	{
		var url = 'http://${ServerTesterConfig.CCC}/version';
		return RequestPromises.get(url)
			.then(function(result) {
				return true;
			});
	}

	@timeout(24000)
	public function testMultipleMonitorEvents() :Promise<Bool>
	{
		//Kill all jobs
		var promises = [];

		function callMonitor(delay) {
			var p = PromiseTools.delay(delay)
				.pipe(function(_) {
					return RetryPromise.retryRegular(getMonitorResult.bind(10000), 5, 1000, 'getMonitorResult');
				})
				.then(function(result) {
					assertEquals(result.OK, true);
					return true;
				});
			promises.push(p);
		}

		function checkOnlyOneTestJob(delay :Int) {
			var p = PromiseTools.delay(delay)
				.pipe(function(_) {
					return RetryPromise.retryRegular(getMonitorJobCount, 5, 1000, 'getMonitorJobCount');
				})
				.then(function(count) {
					assertTrue(count <= 1);
					return true;
				});
			promises.push(p);
		}

		callMonitor(0);
		checkOnlyOneTestJob(0);
		for (i in 3...6) {
			callMonitor(100 * i);
		}

		for (i in 1...6) {
			callMonitor(500 * i);
		}
		checkOnlyOneTestJob(1000);
		checkOnlyOneTestJob(5000);

		for (i in 1...6) {
			callMonitor(1000 * i);
		}

		checkOnlyOneTestJob(10000);

		return Promise.whenAll(promises)
			.thenTrue();
	}

	public static function getMonitorResult(?within :Null<Int>) :Promise<ServiceMonitorRequestResult>
	{
		var url = 'http://${ServerTesterConfig.CCC}${ServiceMonitorRequest.ROUTE_MONITOR}';
		if (within != null) {
			url = '$url?within=$within';
		}
		return RequestPromises.get(url)
			.then(Json.parse);
	}

	public static function getMonitorJobCount() :Promise<Int>
	{
		var url = 'http://${ServerTesterConfig.CCC}${ServiceMonitorRequest.ROUTE_MONITOR_JOB_COUNT}';
		return RequestPromises.get(url)
			.then(Json.parse)
			.then(function(json :{count :Int}) {
				return json.count;
			});
	}
}