package ccc.compute.test;

import js.node.Process;

/**
 * Runs functional tests on a CCC API endpoint
 */
class ServerTester
{
	// static var DEFAULT_TESTS = 'monitor=true';//compute=true&turbojobs=true

	static function main()
	{
		js.npm.sourcemapsupport.SourceMapSupport;
		js.ErrorToJson;
		initGlobalErrorHandler();
		var injector = new Injector();
		injector.map(Injector).toValue(injector); //Map itself

		injector.map(Docker).toValue(new Docker({socketPath:'/var/run/docker.sock'}));

		Promise.promise(true)
			.pipe(function(_) {
				return RedisDependencies
					.mapRedisAndInitializeAll(injector,
						ServerTesterConfig.REDIS_HOST, ServerTesterConfig.REDIS_PORT);
			})
			.pipe(function(_) {
				//Verify that at least a single worker is up and running
				var f = function() {
					var url = 'http://${ServerTesterConfig.CCC}/version';
					return RequestPromises.get(url)
						.then(function(result) {
							return true;
						});
				}
				return RetryPromise.retryRegular(f, 30, 500);
			})
			.pipe(function(_) {
				return runTests(injector);
			});
	}

	static function runTests(injector :Injector)
	{
		var runner = new PromiseTestRunner();

		function addTestClass (cls :Class<Dynamic>) {
			var testCollection :haxe.unit.async.PromiseTest = Type.createInstance(cls, []);
			injector.injectInto(testCollection);
			runner.add(testCollection);
		}

		addTestClass(ccc.compute.test.tests.TestUnit);
		addTestClass(ccc.compute.test.tests.TestCompute);
		addTestClass(ccc.compute.test.tests.TestMonitor);
		addTestClass(ccc.compute.test.tests.TestJobs);
		addTestClass(ccc.compute.test.tests.TestTurboJobs);
		addTestClass(ccc.compute.test.tests.TestFailureConditions);
		//Travis struggles with the scaling tests, likely due to
		//the slowness of the underlying VCPU. Tests that succeed
		//in one repo fail in an identical repo.
		//You'll need to test locally however to catch bugs this
		//test would otherwise catch.
		// if (ServerTesterConfig.TRAVIS_REPO_SLUG != 'dionjwa/cloud-compute-cannon') {
			addTestClass(ccc.compute.test.tests.TestScaling);
		// }

		//Wait on the main server
		var url = 'http://${ServerTesterConfig.CCC}/version';
		var poll = function() {
			return RequestPromises.get(url)
				.then(function(result) {
					return true;
				});
		}
		return RetryPromise.retryRegular(poll, 30, 500, '', true)
			.pipe(function(_) {
				var exitOnFinish = true;
				var disableTrace = false;
				return runner.run(exitOnFinish, disableTrace);
			});
	}

	static function initGlobalErrorHandler()
	{
		Node.process.on(ProcessEvent.UncaughtException, function(err) {
			var errObj = {
				stack:try err.stack catch(e :Dynamic){null;},
				error:err,
				errorJson: try untyped err.toJSON() catch(e :Dynamic){null;},
				errorString: try untyped err.toString() catch(e :Dynamic){null;},
				message:'crash'
			}
			Log.critical(errObj);
			try {
				traceRed(Json.stringify(errObj, null, '  '));
			} catch(e :Dynamic) {
				traceRed(errObj);
			}
			Node.process.exit(1);
		});
	}

	static function runMonitor(injector :Injector)
	{
		Node.setInterval(function() {
			ccc.compute.test.tests.TestMonitor.getMonitorResult(10000)
				.then(function(result) {
					traceGreen(Json.stringify(result));
				})
				.catchError(function(err) {
					traceRed(err);
				});
		}, 4000);
	}
}
