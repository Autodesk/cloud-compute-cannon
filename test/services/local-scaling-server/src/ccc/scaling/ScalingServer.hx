package ccc.scaling;

import ccc.compute.shared.RedisDependencies;

class ScalingServer
{
	static function main()
	{
		//Required for source mapping
		js.npm.sourcemapsupport.SourceMapSupport;

		var injector = new Injector();
		injector.map(Injector).toValue(injector); //Map itself

		injector.map(Docker).toValue(new Docker({socketPath:'/var/run/docker.sock'}));

		Promise.promise(true)
			.pipe(function(_) {
				return RedisDependencies
					.mapRedisAndInitializeAll(injector,
						ScalingServerConfig.REDIS_HOST, ScalingServerConfig.REDIS_PORT);
			})
			.pipe(function(_) {
				return ScalingCommands.inject(injector);
			})
			.pipe(function(_) {
				return createApplication(injector);
			})
			.pipe(function(_) {
				ScalingRoutes.init(injector);
				return createHttpServer(injector);
			});
	}

	static function createApplication(injector :Injector) :Promise<Bool>
	{
		var app = Express.GetApplication();
		injector.map(Application).toValue(app);

		untyped __js__('app.use(require("cors")())');

		app.use(cast js.npm.bodyparser.BodyParser.json({limit: '250mb'}));
		return Promise.promise(true);
	}

	static function createHttpServer(injector :Injector)
	{
		var app = injector.getValue(Application);

		//Actually create the server and start listening
		var server = Http.createServer(cast app);

		injector.map(js.node.http.Server).toValue(server);

		var closing = false;
		Node.process.on('SIGINT', function() {
			Log.warn("Caught interrupt signal");
			if (closing) {
				return;
			}
			closing = true;
			untyped server.close(function() {
				Node.process.exit(0);
			});
		});

		server.listen(ScalingServerConfig.PORT, function() {
			Log.info('Listening http://localhost:${ScalingServerConfig.PORT}');
		});
		return Promise.promise(true);
	}
}
