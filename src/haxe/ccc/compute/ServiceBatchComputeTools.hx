package ccc.compute;

import ccc.storage.ServiceStorage;

import haxe.Json;
import haxe.exter.EitherType;

import js.Node;
import js.node.stream.Readable;
import js.node.Http;
import js.node.http.*;
import js.npm.streamifier.Streamifier;

import minject.Injector;

import promhx.Promise;

import util.DockerRegistryTools;
import util.DockerTools;
import util.DockerUrl;
import util.RedisTools;
import util.streams.StdStreams;

class ServiceBatchComputeTools
{
	public static function createBatchComputeService(config :ServiceConfiguration, app :EitherType<js.node.express.Router,js.npm.Express>, injector :Injector) :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				return ConnectionToolsRedis.getRedisClient()
					.pipe(function(redis) {
						//Pipe specific logs from redis since while developing
						// ServiceBatchComputeTools.pipeRedisLogs(redis);
						injector.map(RedisClient).toValue(redis);
						return InitConfigTools.initAll(redis);
					});
			})
			//Get public/private network addresses
			.pipe(function(_) {
				return Promise.promise(true)
					.pipe(function(_) {
						return WorkerProviderTools.getPrivateHostName(config.providers[0])
							.then(function(hostname) {
								Constants.SERVER_HOSTNAME_PRIVATE = hostname;
								Log.debug({server_status:status, SERVER_HOSTNAME_PRIVATE:Constants.SERVER_HOSTNAME_PRIVATE});
								return true;
							});
					})
					.pipe(function(_) {
						return WorkerProviderTools.getPublicHostName(config.providers[0])
							.then(function(hostname) {
								Constants.SERVER_HOSTNAME_PUBLIC = hostname;
								Log.debug({server_status:status, SERVER_HOSTNAME_PUBLIC:Constants.SERVER_HOSTNAME_PUBLIC});
								return true;
							});
					});
			})
			.then(function(_) {
				status = ServerStatus.BuildingServices_3_4;
				Log.debug({server_status:status});
				//Build and inject the app logic
				//Create services
				var workerProviders :Array<ccc.compute.workers.WorkerProvider> = config.providers.map(WorkerProviderTools.getProvider);
				injector.map(WorkerProvider).toValue(workerProviders[0]);

				//The queue manager
				var schedulingService = new ccc.compute.ServiceBatchCompute();
				injector.map(ServiceBatchCompute).toValue(schedulingService);

				//Monitor workers
				var workerManager = new WorkerManager();
				injector.map(WorkerManager).toValue(workerManager);
				//This actually executes the jobs
				var jobManager = new Jobs();
				injector.injectInto(jobManager);

				//Inject everything!
				injector.injectInto(storage);
				injector.injectInto(schedulingService);
				injector.injectInto(workerManager);
				for (workerProvider in workerProviders) {
					injector.injectInto(workerProvider);
				}

				//RPC machinery
				//Server infrastructure. This automatically handles client JSON-RPC remoting and other API requests
				app.use(SERVER_API_URL, cast schedulingService.router());

				//Websocket server for getting job finished notifications
				websocketServer(injector.getValue(RedisClient), server, storage);
				websocketServer(injector.getValue(RedisClient), serverHTTP, storage);


				//After all API routes, assume that any remaining requests are for files.
				//This is nice for local development
				if (storageConfig.type == StorageSourceType.Local) {
					// Show a nice browser for the local file system.
					Log.debug('Setting up static file server for output from Local Storage System at: ${config.storage.rootPath}');
					app.use('/', Node.require('serve-index')(config.storage.rootPath, {'icons': true}));
				}
				//Setup a static file server to serve job results
				app.use('/', StorageRestApi.staticFileRouter(storage));

				status = ServerStatus.Ready_4_4;
				Log.debug({server_status:status});
				if (Node.process.send != null) {//If spawned via a parent process, send will be defined
					Node.process.send(Constants.IPC_MESSAGE_READY);
				}

				//Run internal tests
				Log.debug('Running server functional tests');
				promhx.RequestPromises.get('http://localhost:${SERVER_DEFAULT_PORT}${SERVER_RPC_URL}/server-tests')
					.then(function(out) {
						try {
							var results = Json.parse(out);
							var result = results.result;
							if (result.success) {
								Log.info({TestResults:result});
								traceGreen(Json.stringify(result, null, '  '));
							} else {
								Log.error({TestResults:result});
								traceRed(Json.stringify(result, null, '  '));
							}
						} catch(err :Dynamic) {
							Log.error({error:err, message:'Failed to parse test results'});
						}
					})
					.catchError(function(err) {
						Log.error({error:err, message:'failed tests!'});
					});
			});
	}


	public static function pipeRedisLogs(redis :js.npm.RedisClient, ?streams :StdStreams)
	{
		if (streams == null) {
			streams = {out:js.Node.process.stdout, err:js.Node.process.stderr};
		}
		var stdconvert :String->String = untyped __js__('require("cli-color").red.bgWhite');
		var errconvert :String->String = untyped __js__('require("cli-color").red.bold.bgWhite');
		var stdStream = RedisTools.createPublishStream(redis, ComputeQueue.REDIS_CHANNEL_LOG_INFO);
		stdStream
			.then(function(msg) {
				streams.out.write(stdconvert('[REDIS] ' + msg + '\n'));
			});
		var errStream = RedisTools.createPublishStream(redis, ComputeQueue.REDIS_CHANNEL_LOG_ERROR);
		errStream
			.then(function(msg) {
				streams.err.write(errconvert(js.npm.clicolor.CliColor.red('[REDIS] ' + msg + '\n')));
			});
	}

	public static function checkRegistryForDockerUrl(url :DockerUrl) :Promise<DockerUrl>
	{
		if (url.registryhost != null) {
			return Promise.promise(url);
		} else {
			var host = ConnectionToolsRegistry.getRegistryAddress();
			return DockerRegistryTools.isImageIsRegistry(host, url.repository, url.tag)
				.then(function(isInRegistry) {
					if (isInRegistry) {
						url.registryhost = host;
						return url;
					} else {
						return url;
					}
				});
		}
	}
}