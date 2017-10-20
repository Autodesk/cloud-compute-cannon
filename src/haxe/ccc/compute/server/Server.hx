package ccc.compute.server;

import ccc.compute.server.execution.routes.ServerCommands;

import haxe.remoting.JsonRpc;
import haxe.DynamicAccess;

import js.node.Process;
import js.node.http.*;
import js.npm.docker.Docker;
import js.npm.express.Express;
import js.npm.express.Application;
import js.npm.express.Request;
import js.npm.express.Response;
import js.npm.JsonRpcExpressTools;
import js.npm.redis.RedisClient;

import minject.Injector;

import ccc.storage.*;

import util.RedisTools;
import util.DockerTools;

/**
 * Represents a queue of compute jobs in Redis
 * Lots of ideas taken from http://blogs.bronto.com/engineering/reliable-queueing-in-redis-part-1/
 */
class Server
{
	static var DEFAULT_TESTS = 'monitor=true';//compute=true&turbojobs=true

	public static var StorageService :ServiceStorage;
	public static var StatusStream :Stream<JobStatsData>;
	static var status :ServerStartupState;

	static function main()
	{
		//Required for source mapping
		js.npm.sourcemapsupport.SourceMapSupport;
		//Embed various files
		util.EmbedMacros.embedFiles('etc', ["etc/hxml/.*"]);
		js.ErrorToJson;
		// monitorMemory();

		var injector :ServerState = new Injector();
		injector.map(Injector).toValue(injector); //Map itself
		injector.map('Array<Dynamic>', 'Injectees').toValue([]);

		initLogging(injector);
		injector.setStatus(ServerStartupState.Booting);
		initProcess();
		initGlobalErrorHandler();
		initAppConfig(injector);
		initStorage(injector);
		ServerPaths.initAppPaths(injector);
		runServer(injector);
	}

	static function initProcess()
	{
		js.Node.process.stdout.setMaxListeners(100);
		js.Node.process.stderr.setMaxListeners(100);

		//Load env vars from an .env file if present
		Node.require('dotenv').config({path: './.env', silent: true});
		//In a testing environment, we need to mount the .env
		//from a different location otherwise node_modules get
		//mounted in the base dir, and those modules are for
		//a different OS
		Node.require('dotenv').config({path: './config/.env', silent: true});

		//Sanity checks
		if (util.DockerTools.isInsideContainer() && !ConnectionToolsDocker.isLocalDockerHost()) {
			Log.critical('/var/run/docker.sock is not mounted and the server is in a container. How does the server call docker commands?');
			js.Node.process.exit(-1);
		}
	}

	static function initLogging(injector :ServerState)
	{
		if (ServerConfig.LOGGING_DISABLE) {
			untyped __js__('console.log = function() {}');
			Log.debug({LOG_LEVEL: 'disabled'}.add(LogEventType.LogLevel));
			Logger.GLOBAL_LOG_LEVEL = 100;
		} else {
			Logger.GLOBAL_LOG_LEVEL = LogTools.logStringToLevel(ServerConfig.LOG_LEVEL);
			Log.debug({LOG_LEVEL: ServerConfig.LOG_LEVEL}.add(LogEventType.LogLevel));
		}

		injector.map(AbstractLogger).toValue(Logger.log);
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
			//Ensure crash is logged before exiting.
			try {
				if (ServerConfig.FLUENT_HOST != null) {
					ccc.compute.server.logs.FluentTools.logToFluent(Json.stringify(errObj), function() {
						Node.process.exit(1);
					});
				} else {
					Node.process.exit(1);
				}
			} catch(e :Dynamic) {
				Node.process.exit(1);
			}
		});
	}

	static function initAppConfig(injector :ServerState)
	{
		injector.setStatus(ServerStartupState.LoadingConfig);
		var config :ServiceConfiguration = InitConfigTools.getConfig();
		Assert.notNull(config);
		Assert.notNull(config.providers, 'config.providers == null');
		Assert.notNull(config.providers[0], 'No providers');

		Log.debug({config:LogTools.removePrivateKeys(config)});

		var env :DynamicAccess<String> = Node.process.env;

		var CONFIG_PATH :String = Reflect.hasField(env, ENV_VAR_COMPUTE_CONFIG_PATH) && Reflect.field(env, ENV_VAR_COMPUTE_CONFIG_PATH) != "" ? Reflect.field(env, ENV_VAR_COMPUTE_CONFIG_PATH) : SERVER_MOUNTED_CONFIG_FILE_DEFAULT;

		mapEnvVars(injector);

		for (key in Reflect.fields(config)) {
			if (key != 'storage' && key != 'providers') {
				Reflect.setField(env, key, Reflect.field(config, key));
			}
		}

		injector.map('ccc.compute.shared.ServiceConfiguration').toValue(config);
		injector.map('ccc.compute.shared.ServiceConfigurationWorkerProvider').toValue(config.providers[0]);

		var injectionTest = new ConfigInjectionTest();
		injector.injectInto(injectionTest);
		Assert.notNull(injectionTest.config);
		Assert.notNull(injectionTest.workerConfig);

		for (v in [['ccc.compute.shared.ServiceConfiguration'], ['ccc.compute.shared.ServiceConfigurationWorkerProvider']]) {
			if (v.length > 1) {
				Assert.notNull(injector.getValue(v[0], v[1]), 'Missing injector.getValue(${v[0]}, ${v[1]})');
			} else {
				Assert.notNull(injector.getValue(v[0]), 'Missing injector.getValue(${v[0]})');
			}
		}

		injector.map(Docker).toValue(new Docker({socketPath:'/var/run/docker.sock'}));

		var workerInternalState :WorkerStateInternal = {
			ncpus: 0,
			timeLastHealthCheck: null,
			jobs: [],
			id: null,
			health: null
		};
		injector.map('ccc.WorkerStateInternal').toValue(workerInternalState);

		var localhost :Host = 'localhost:$SERVER_DEFAULT_PORT';
		injector.map(Host, 'serverhost').toValue(localhost);
		var serverHostRPCAPI : UrlString = 'http://${localhost}${SERVER_RPC_URL}';
		injector.map(UrlString, 'localRPCApi').toValue(serverHostRPCAPI);
	}



	static function createHttpServer(injector :ServerState)
	{
		injector.setStatus(ServerStartupState.StartingHttpServer);
		var app = injector.getValue(Application);
		var env :DynamicAccess<String> = Node.process.env;

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

		var PORT :Int = Reflect.hasField(env, 'PORT') ? Std.int(Reflect.field(env, 'PORT')) : 9000;
		server.listen(PORT, function() {
			Log.info(LogFieldUtil.addServerEvent({message:'Listening http://localhost:$PORT'}, ServerEventType.STARTED));
		});
	}

	static function initRedis(injector :ServerState) :Promise<Bool>
	{
		injector.setStatus(ServerStartupState.ConnectingToRedis);
		var env :DynamicAccess<String> = Node.process.env;
		return ConnectionToolsRedis.getRedisClient()
			.then(function(redis) {
				Assert.notNull(redis, 'ServerRedisClient is null');
				Assert.notNull(redis.client, 'ServerRedisClient.client is null');
				injector.map(ServerRedisClient).toValue(redis);
				injector.map(RedisClient).toValue(redis.client);
				return redis;
			})
			.pipe(function(redis) {
				//Init redis dependencies
				return RedisDependencies.initDependencies(injector);
			})
			.thenTrue();
	}

	static function initSaveConfigToRedis(injector :ServerState) :Promise<Bool>
	{
		injector.setStatus(ServerStartupState.SavingConfigToRedis);
		var serverRedis :ServerRedisClient = injector.getValue(ServerRedisClient);
		Assert.notNull(serverRedis, 'serverRedis is null');
		var redis :RedisClient = serverRedis.client;
		Assert.notNull(redis, 'redis is null');

		var config :ServiceConfigurationWorkerProvider = injector.getValue('ccc.compute.shared.ServiceConfigurationWorkerProvider');
		return Promise.promise(true)
			.pipe(function(_) {
				return RedisPromises.hset(redis, CONFIG_HASH, CONFIG_HASH_WORKERS_MAX, '${config.maxWorkers}');
			})
			.pipe(function(_) {
				return RedisPromises.hset(redis, CONFIG_HASH, CONFIG_HASH_WORKERS_MIN, '${config.minWorkers}');
			})
			.thenTrue();
	}

	static function initStorage(injector :ServerState)
	{
		injector.setStatus(ServerStartupState.CreateStorageDriver);
		var config :ServiceConfiguration = injector.getValue('ccc.compute.shared.ServiceConfiguration');

		/* Storage*/
		Assert.notNull(config.storage);
		var storageConfig :StorageDefinition = config.storage;
		var storage :ServiceStorage = StorageTools.getStorage(storageConfig);
		Assert.notNull(storage);
		StorageService = storage;
		injector.map('ccc.storage.StorageDefinition').toValue(storageConfig);
		injector.map(ccc.storage.ServiceStorage).toValue(storage);
		injector.getValue('Array<Dynamic>', 'Injectees').push(storage);
	}

	static function initWorker(injector :ServerState) :Promise<Bool>
	{
		var workerManager = new ccc.compute.worker.WorkerStateManager();
		injector.map(ccc.compute.worker.WorkerStateManager).toValue(workerManager);
		injector.injectInto(workerManager);
		return workerManager.ready;
	}

	static function runServer(injector :ServerState) :Promise<Bool>
	{
		Constants.DOCKER_CONTAINER_ID = DockerTools.getContainerId();

		var env :DynamicAccess<String> = Node.process.env;

		var config :ServiceConfiguration = injector.getValue('ccc.compute.shared.ServiceConfiguration');

		createHttpServer(injector);

		return Promise.promise(true)
			.pipe(function(_) {
				return DockerTools.getThisContainerName()
					.then(function(containerName) {
						Constants.DOCKER_CONTAINER_NAME = containerName.startsWith('/') ? containerName.substr(1) : containerName;
						return true;
					});
			})
			.pipe(function(_) {
				return initRedis(injector);
			})
			.pipe(function(_) {
				return initSaveConfigToRedis(injector);
			})
			.then(function(_) {
				StatusStream = JobStream.getStatusStream();
				injector.map("promhx.Stream<ccc.JobStatsData>", "StatusStream").toValue(StatusStream);
				StatusStream.catchError(function(err) {
					Log.error(err);
				});
				var activeJobStream = JobStream.getActiveJobStream();
				injector.map("promhx.Stream<Array<ccc.JobId>>", "ActiveJobStream").toValue(activeJobStream);

				var finishedJobStream = JobStream.getFinishedJobStream();
				injector.map("promhx.Stream<Array<ccc.JobId>>", "FinishedJobStream").toValue(finishedJobStream);
			})
			.pipe(function(_) {
				injector.setStatus(ServerStartupState.BuildingServices);
				return initWorker(injector);
			})
			.then(function(_) {
				trace('ServiceMonitorRequest');
				ServiceMonitorRequest.init(injector);
				return true;
			})
			.then(function(_) {

				var serverRedis :ServerRedisClient = injector.getValue(ServerRedisClient);
				var redis :RedisClient = serverRedis.client;

				//Inject everything!
				var injectees :Array<Dynamic> = injector.getValue('Array<Dynamic>', 'Injectees');
				for(injectee in injectees) {
					injector.injectInto(injectee);
				}

				//RPC machinery
				var serviceRoutes = ccc.compute.server.execution.routes.RpcRoutes.router(injector);
				injector.getValue(Application).use(SERVER_API_URL, serviceRoutes);

				//Also start using versioned APIs
				var serviceRoutesV1 = ccc.compute.server.execution.routes.RpcRoutes.routerVersioned(injector);
				injector.getValue(Application).use(serviceRoutesV1);

				initWebsocketServer(injector);
				initStaticFileServing(injector);

				return true;
			})
			.then(function(_) {
				injector.setStatus(ServerStartupState.Ready);
				if (Node.process.send != null) {//If spawned via a parent process, send will be defined
					Node.process.send(Constants.IPC_MESSAGE_READY);
				}
				return true;
			});
	}

	static function runFunctionalTests(injector :ServerState)
	{
		var env :DynamicAccess<String> = Node.process.env;
		//Run internal tests
		var isTravisBuild = ServerConfig.TRAVIS;
		var disableStartTest = ServerConfig.DISABLE_STARTUP_TESTS;
		if (!disableStartTest) {
			traceGreen('Running server functional tests');
			promhx.RequestPromises.get('http://localhost:${SERVER_DEFAULT_PORT}${SERVER_RPC_URL}/server-tests?${isTravisBuild ? "core=true&storage=true&compute=true&jobs=true&turbojobs=true" : DEFAULT_TESTS}')
				.then(function(out) {
					try {
						var results = Json.parse(out);
						var result = results.result;
						if (result.success) {
							traceGreen(Json.stringify(result));
						} else {
							Log.error({TestResults:result});
							traceRed(Json.stringify(result));
						}
						if (isTravisBuild) {
							Node.process.exit(result.success ? 0 : 1);
						}
					} catch(err :Dynamic) {
						Log.error({error:err, message:'Failed to parse test results'});
						if (isTravisBuild) {
							Node.process.exit(1);
						}
					}
				})
				.catchError(function(err) {
					Log.error({error:err, message:'failed tests!'});
					if (isTravisBuild) {
						Node.process.exit(1);
					}
				});
		}
	}

	static function initStaticFileServing(injector :ServerState)
	{
		var app = injector.getValue(Application);

		//Serve metapages dashboards
		app.use('/', Express.Static('./web'));
		// app.use('/dashboard', Express.Static('./clients/dashboard'));
		app.use('/node_modules', Express.Static('./node_modules'));

		var storage :ServiceStorage = injector.getValue(ServiceStorage);
		var config :ServiceConfiguration = injector.getValue('ccc.compute.shared.ServiceConfiguration');
		/* Storage*/
		Assert.notNull(config.storage);
		var storageConfig :StorageDefinition = config.storage;

		//After all API routes, assume that any remaining requests are for files.
		//This is nice for local development
		if (storageConfig.type == StorageSourceType.Local) {
			// Show a nice browser for the local file system.
			Log.debug('Setting up static file server for output from Local Storage System at: ${config.storage.rootPath}');
			app.use('/', Node.require('serve-index')(config.storage.rootPath, {'icons': true}));
		}
		//Setup a static file server to serve job results
		app.use('/', cast StorageRestApi.staticFileRouter(storage));
	}

	static function initWebsocketServer(injector :ServerState)
	{
		injector.setStatus(ServerStartupState.StartWebsocketServer);

		var wss = new ccc.compute.server.services.ws.ServiceWebsockets();
		injector.map(ccc.compute.server.services.ws.ServiceWebsockets).toValue(wss);
		injector.injectInto(wss);
	}

	static function mapEnvVars(injector :Injector)
	{
		traceGreen('Mapping ${ServerConfig.REDIS_HOST} to injector REDIS_HOST');
		//Docker links can set the REDIS_PORT to the full url. Need to check for this.
		var port :Int = if (ServerConfig.REDIS_PORT == null) {
			6379;
		} else {
			ServerConfig.REDIS_PORT;
		}
		traceGreen('Mapping ${port} to injector REDIS_PORT');
		injector.map(String, 'REDIS_HOST').toValue(ServerConfig.REDIS_HOST);
		injector.map(Int, 'REDIS_PORT').toValue(port);
	}

	static function monitorMemory()
	{
		var memwatch :js.node.events.EventEmitter<Dynamic> = Node.require('memwatch-next');
		memwatch.on('stats', function(data) {
			Log.debug({memory_stats:data});
		});
		memwatch.on('leak', function(data) {
			Log.debug({memory_leak:data});
		});
	}
}

class ConfigInjectionTest
{
	@inject public var workerConfig :ServiceConfigurationWorkerProvider;
	@inject public var config :ServiceConfiguration;
	public function new(){}
}
