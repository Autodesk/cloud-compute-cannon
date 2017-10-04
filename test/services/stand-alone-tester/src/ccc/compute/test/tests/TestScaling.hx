package ccc.compute.test.tests;

class TestScaling
	extends haxe.unit.async.PromiseTest
{
	/**
	 * Calls the running scaling server (that has its
	 * own test(s)).
	 */
	@timeout(300000)
	public function testLambdaScaling() :Promise<Bool>
	{
		var url = 'http://${ServerTesterConfig.CCC_SCALING}/test';
		return RequestPromises.get(url)
			.then(Json.parse)
			.then(function(result :ResponseDefSuccess<CompleteTestResult>) {
				if (result.result.success) {
					traceGreen(Json.stringify(result.result, null, '  '));
				} else {
					traceRed(Json.stringify(result.result, null, '  '));
				}
				assertTrue(result.result.success);
				return true;
			});
	}
}