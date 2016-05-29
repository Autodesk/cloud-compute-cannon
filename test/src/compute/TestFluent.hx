package compute;

import js.node.Http;
import js.npm.Express;

import promhx.Promise;
import promhx.deferred.DeferredPromise;
import promhx.RequestPromises;

import ccc.compute.workers.WorkerProviderTools;
import ccc.compute.workers.WorkerProviderBoot2Docker;

class TestFluent extends TestBase
{
	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.then(function(_) {
				_env = cast Reflect.copy(js.Node.process.env);
				var config = InitConfigTools.getConfigFromEnv();
				if (config != null && !InitConfigTools.isPkgCloudConfigured(config)) {
					_env = null;
				}
				return true;
			});
	}

	@timeout(100000)
	public function testFluentStartAndStop()
	{
		var docker = WorkerProviderBoot2Docker.getLocalDocker();
		return Promise.promise(true)
			// .pipe(function(_) {
			// 	return WorkerProviderTools.isFluentCollectorContainerRunning(docker)
			// 		.pipe(function(isRunning) {
			// 			assertTrue(!isRunning);
			// 			return WorkerProviderTools.ensureFluentCollectorContainer(docker);
			// 		});
			// })
			.pipe(function(_) {
				var promise = new DeferredPromise();
				//Create a web server, and ping the fluent collector. One of the
				//plugins calls the URL in the log entry
				var app = new Express();
				app.get('/fluentcheck', function(req, res) {
					res.send('OK');
					promise.resolve(true);
				});
				var server = Http.createServer(cast app);
				var PORT = 8219;
				server.listen(PORT, function() {
					Log.info('Listening http://localhost:$PORT');
					//curl -X POST -d 'json={"url":"http://localhost:8219"}' http://docker:9880/callback
					//docker run --rm -ti tutum/curl curl -X POST -d 'json={"url":"http://localhost:8219"}' http://localhost:9880/callback
					RequestPromises.post('http://docker:9880/callback', 'json={"url":"http://localhost:$PORT"}')
						.then(function(response) {
							trace('response=${response}');
						})
						.catchError(function(err) {
							promise.boundPromise.reject(err);
						});
				});


				return promise.boundPromise;
			});
	}

	public function new() {}
}