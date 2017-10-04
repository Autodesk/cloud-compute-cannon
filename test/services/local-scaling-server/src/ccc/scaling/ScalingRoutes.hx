package ccc.scaling;

import haxe.remoting.JsonRpc;

import haxe.unit.async.PromiseTest;
import haxe.unit.async.PromiseTestRunner;

import js.npm.express.ExpressResponse;
import js.npm.express.ExpressRequest;

import t9.js.jsonrpc.Routes;
import t9.remoting.jsonrpc.Context;

class ScalingRoutes
{
	@rpc({
		alias:'test',
	})
	public function test() :Promise<CompleteTestResult>
	{
		var runner = new PromiseTestRunner();

		function addTestClass (cls :Class<Dynamic>) {
			var testCollection :haxe.unit.async.PromiseTest = Type.createInstance(cls, []);
			_injector.injectInto(testCollection);
			runner.add(testCollection);
		}

		addTestClass(Tests);
		var exitOnFinish = false;
		var disableTrace = false;
		return runner.run(exitOnFinish, disableTrace)
			.then(function(result) {
				result.tests.iter(function(test) {
					if (test.error != null) {
						traceRed(test.error.replace('\\n', '\n'));
					}
				});
				return result;
			});
	}

	@rpc({
		alias:'createworker'
	})
	public function createworker() :Promise<{success:Bool,ContainerId:String}>
	{
		return ScalingCommands.createWorker()
			.then(function(containerId) {
				return {success:true, ContainerId:containerId};
			});
	}

	@rpc({
		alias:'killworker'
	})
	public function killworker() :Promise<{success:Bool,message:String}>
	{
		return ScalingCommands.getAllDockerWorkerIds()
			.pipe(function(ids) {
				if (ids.length > 0) {
					return ScalingCommands.killWorker(ids[0])
						.then(function(_) {
							return {success:true, message: 'Worker killed: ${ids[0]}'};
						});
				} else {
					return Promise.promise({success:false, message: 'No workers'});
				}
			});
	}

	@rpc({
		alias:'testpostjob'
	})
	public function testpostjob() :Promise<JobResult>
	{
		var jobRequest = ServerTestTools.createTestJobAndExpectedResults('testpostjob', 1);
		var f = function() return ccc.compute.client.js.ClientJSTools.postJob(ScalingServerConfig.CCC, jobRequest.request, {});
		return RetryPromise.retryRegular(f, 5, 500);
	}

	public static function init(injector :Injector)
	{
		//Rpc machinery
		if (!injector.hasMapping(Context)) {
			var context = new t9.remoting.jsonrpc.Context();
			injector.map(Context).toValue(context);
		}
		var context = injector.getValue(Context);

		var routes = new ScalingRoutes();
		injector.injectInto(routes);
		injector.map(ScalingRoutes).toValue(routes);

		//Express route mounting
		var router = js.npm.express.Express.GetRouter();
		var timeout = 1000*60*30;//30m
		router.post(cast Routes.generatePostRequestHandler(context, timeout));
		router.get('/*', Routes.generateGetRequestHandler(context, '/', timeout));

		injector.getValue(Application).use('/', router);
	}

	function new() {}

	@post
	public function postInject()
	{
		_context.registerService(this);
	}

	@inject public var _context :Context;
	@inject public var _injector :Injector;
}