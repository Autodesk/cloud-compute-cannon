package ccc.compute.server;

import ccc.compute.server.execution.routes.ServerCommands;

import haxe.remoting.JsonRpc;
import haxe.DynamicAccess;

import js.node.Process;
import js.node.http.*;
import js.npm.RedisClient;
import js.npm.docker.Docker;
import js.node.express.Express;
import js.node.express.Application;
import js.node.express.ExpressRequest;
import js.node.express.ExpressResponse;
import js.npm.JsonRpcExpressTools;
import js.npm.Ws;
import js.npm.RedisClient;

import minject.Injector;

import ccc.storage.*;

import util.RedisTools;
import util.DockerTools;


enum ServerStartupState {
	Booting;
	LoadingConfig;
	CreateStorageDriver;
	StartingHttpServer;
	ConnectingToRedis;
	SavingConfigToRedis;
	BuildingServices;
	StartWebsocketServer;
	Ready;
}

/**
 * Represents a queue of compute jobs in Redis
 * Lots of ideas taken from http://blogs.bronto.com/engineering/reliable-queueing-in-redis-part-1/
 */
class Server
{
	public static var StorageService :ServiceStorage;
	public static var StatusStream :Stream<JobStatusUpdate>;
	static var status :ServerStartupState;

	inline static function updateStatus(s :ServerStartupState)
	{
		status = s;
		Log.info({status:'${status} ${Type.getEnumConstructs(ServerStartupState).indexOf(Type.enumConstructor(status)) + 1} / ${Type.getEnumConstructs(ServerStartupState).length}'});
	}

	static function main()
	{
		updateStatus(ServerStartupState.Booting);

		//Required for source mapping
		js.npm.sourcemapsupport.SourceMapSupport;
		//Embed various files
		util.EmbedMacros.embedFiles('etc', ["etc/hxml/.*"]);
		ErrorToJson;
		// monitorMemory();

		var injector = new Injector();
		injector.map(Injector).toValue(injector); //Map itself
		injector.map('Array<Dynamic>', 'Injectees').toValue([]);

		initProcess();
		initGlobalErrorHandler();
		initLogging(injector);
		initAppConfig(injector);
		initStorage(injector);
		initAppPaths(injector);
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

	static function initLogging(injector :Injector)
	{
		var env :DynamicAccess<String> = Node.process.env;

		if (env[ENV_VAR_DISABLE_LOGGING] == 'true') {
			untyped __js__('console.log = function() {}');
			Log.info('Disabled logging');
			Logger.GLOBAL_LOG_LEVEL = 100;
		} else {
			if (Reflect.hasField(env, ENV_LOG_LEVEL)) {
				var newLogLevel = Std.parseInt(env[ENV_LOG_LEVEL]);
				Logger.GLOBAL_LOG_LEVEL = newLogLevel;
			}
			Log.debug('GLOBAL_LOG_LEVEL=${Logger.GLOBAL_LOG_LEVEL}');
		}

		if (Reflect.field(env, ENV_ENABLE_FLUENT) == 'false' || Reflect.field(env, ENV_ENABLE_FLUENT) == '0') {
			Logger.IS_FLUENT = false;
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
				if (Logger.IS_FLUENT) {
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

	static function initAppConfig(injector :Injector)
	{
		updateStatus(ServerStartupState.LoadingConfig);
		var config :ServiceConfiguration = InitConfigTools.getConfig();
		Assert.notNull(config);
		Assert.notNull(config.providers, 'config.providers == null');
		Assert.notNull(config.providers[0], 'No providers');

		Log.debug({config:LogTools.removePrivateKeys(config)});

		var env :DynamicAccess<String> = Node.process.env;

		var CONFIG_PATH :String = Reflect.hasField(env, ENV_VAR_COMPUTE_CONFIG_PATH) && Reflect.field(env, ENV_VAR_COMPUTE_CONFIG_PATH) != "" ? Reflect.field(env, ENV_VAR_COMPUTE_CONFIG_PATH) : SERVER_MOUNTED_CONFIG_FILE_DEFAULT;

		Log.debug({provider:config.providers[0].type, storage:config.storage.type});

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
		injector.map('ccc.compute.shared.WorkerStateInternal').toValue(workerInternalState);

		var localhost :Host = 'localhost:$SERVER_DEFAULT_PORT';
		injector.map(Host, 'serverhost').toValue(localhost);
		var serverHostRPCAPI : UrlString = 'http://${localhost}${SERVER_RPC_URL}';
		injector.map(UrlString, 'localRPCApi').toValue(serverHostRPCAPI);
	}

	static function initAppPaths(injector :Injector)
	{
		var config :ServiceConfiguration = injector.getValue('ccc.compute.shared.ServiceConfiguration');

		var app = Express.GetApplication();
		injector.map(Application).toValue(app);

		untyped __js__('app.use(require("cors")())');

		app.get('/version', function(req, res) {
			var versionBlob = ServerCommands.version();
			res.send(versionBlob.VERSION);
		});

		function test(req, res) {
			var serviceTests :ccc.compute.server.tests.ServiceTests = injector.getValue(ccc.compute.server.tests.ServiceTests);
			if (serviceTests == null) {
				res.status(500).json({status:status, success:false});
			} else {
				serviceTests.testSingleJob()
					.then(function(ok) {
						res.json({success:ok});
					}).catchError(function(err) {
						res.status(500).json(cast {error:err, success:false});
					});
			}
		}

		app.get('/healthcheck', function(req, res) {
			test(req, res);
		});

		app.get('/test', function(req, res) {
			test(req, res);
		});

		app.get('/version_extra', function(req, res) {
			var versionBlob = ServerCommands.version();
			res.send(Json.stringify(versionBlob));
		});

		// app.get('/config', function(req, res) {
		// 	var configCopy = LogTools.removePrivateKeys(config);
		// 	res.send(Json.stringify(configCopy, null, '  '));
		// });

		//Check if server is listening
		app.get(Constants.SERVER_PATH_CHECKS, function(req, res) {
			res.send(Constants.SERVER_PATH_CHECKS_OK);
		});
		//Check if server is listening
		app.get(Constants.SERVER_PATH_STATUS, function(req, res) {
			res.send('{"status":"${status}"}');
		});

		//Check if server is ready
		app.get(SERVER_PATH_READY, cast function(req, res) {
			if (status == ServerStartupState.Ready) {
				Log.debug('${SERVER_PATH_READY}=YES');
				res.status(200).end();
			} else {
				Log.debug('${SERVER_PATH_READY}=NO');
				res.status(500).end();
			}
		});

		//Check if server is ready
		app.get('/crash', cast function(req, res) {
			Node.process.stdout.write('NAKEDBUS\n');
			Node.process.nextTick(function() {
				throw new Error('FAKE CRASH');
			});
		});

		app.get('/log2*', cast function(req, res) {
			Node.process.stdout.write('\nPOLYGLOT\n');
			res.status(200).end();
		});

		//Check if server is ready
		app.get(SERVER_PATH_WAIT, cast function(req, res) {
			function check() {
				if (status == ServerStartupState.Ready) {
					res.status(200).end();
					return true;
				} else {
					return false;
				}
			}
			var ended = false;
			req.once(ReadableEvent.Close, function() {
				ended = true;
			});
			var poll;
			poll = function() {
				if (!check() && !ended) {
					Node.setTimeout(poll, 1000);
				}
			}
			poll();
		});

		//Check if server is listening
		app.get('/log', function(req, res) {
			var logMessageString = 'somestring';
			Log.debug(logMessageString);
			Log.debug({'foo':'bar'});
			res.send('Logged some shit');
		});

		//Check if server is listening
		app.get('/jobcount', function(req, res :ExpressResponse) {
			if (injector.hasMapping(WorkerController)) {
				var wc :WorkerController = injector.getValue(WorkerController);
				wc.jobCount()
					.then(function(count) {
						res.json({count:count});
					})
					.catchError(function(err) {
						res.status(500).json(cast {error:err});
					});
			} else {
				res.json({count:0});
			}
		});

		//Quick summary of worker jobs counts for scaling control.
		app.get('/worker-jobs', function(req, res :ExpressResponse) {
			if (injector.hasMapping(RedisClient)) {
				var redis :RedisClient = injector.getValue(RedisClient);
				var jobs :Jobs = redis;
				var jobStatusTools :JobStateTools = redis;
				jobs.getAllWorkerJobs()
					.pipe(function(result) {
						return jobStatusTools.getJobsWithStatus(JobStatus.Pending)
							.then(function(jobIds) {
								res.json({
									waiting:jobIds,
									workers:result
								});
							});
					})
					.catchError(function(err) {
						res.status(500).json(cast {error:err});
					});
			} else {
				res.json({});
			}
		});
	}

	static function createHttpServer(injector :Injector)
	{
		updateStatus(ServerStartupState.StartingHttpServer);
		var app = injector.getValue(Application);
		var env :DynamicAccess<String> = Node.process.env;

		//Actually create the server and start listening
		var appHandler :IncomingMessage->ServerResponse->(Error->Void)->Void = cast app;
		var requestErrorHandler = function(err :Dynamic) {
			Log.error({error:err != null && err.stack != null ? err.stack : err, message:'Uncaught error'});
		}
		var server = Http.createServer(function(req, res) {
			appHandler(req, res, requestErrorHandler);
		});
		var serverHTTP = Http.createServer(function(req, res) {
			appHandler(req, res, requestErrorHandler);
		});

		injector.map(js.node.http.Server, 'Server1').toValue(server);
		injector.map(js.node.http.Server, 'Server2').toValue(serverHTTP);

		var closing = false;
		Node.process.on('SIGINT', function() {
			Log.warn("Caught interrupt signal");
			if (closing) {
				return;
			}
			closing = true;
			untyped server.close(function() {
				untyped serverHTTP.close(function() {
					// if (workerProviders != null) {
					// 	return Promise.whenAll(workerProviders.map(function(workerProvider) {
					// 		return workerProvider.dispose();
					// 	}))
					// 	.then(function(_) {
					// 		Node.process.exit(0);
					// 		return true;
					// 	});
					// } else {
					// 	Node.process.exit(0);
					// 	return Promise.promise(true);
					// }
					Node.process.exit(0);
				});
			});
		});

		var PORT :Int = Reflect.hasField(env, 'PORT') ? Std.int(Reflect.field(env, 'PORT')) : 9000;
		server.listen(PORT, function() {
			Log.info('Listening http://localhost:$PORT');
			serverHTTP.listen(SERVER_HTTP_PORT, function() {
				Log.info('Listening http://localhost:$SERVER_HTTP_PORT');
			});
		});
	}

	static function initRedis(injector :Injector) :Promise<Bool>
	{
		updateStatus(ServerStartupState.ConnectingToRedis);
		var env :DynamicAccess<String> = Node.process.env;
		return ConnectionToolsRedis.getRedisClient()
			.pipe(function(redis) {

				injector.map(RedisClient).toValue(redis);

				if (Reflect.field(env, ENV_CLEAR_DB_ON_START) == 'true') {
					Log.warn('!Deleting all keys prior to starting stack');
					return promhx.RedisPromises.deleteAllKeys(redis)
						.then(function(_) {
							return redis;
						});
				} else {
					return Promise.promise(redis);
				}
			})
			.pipe(function(redis :RedisClient) {
				//Init redis dependencies
				return Promise.promise(true)
					.pipe(function(_) {
						var jobStats :JobStats = redis;
						return jobStats.init();
					})
					.pipe(function(_) {
						var jobStateTools :JobStateTools = redis;
						return jobStateTools.init();
					})
					.pipe(function(_) {
						var jobs :Jobs = redis;
						return jobs.init();
					});
			})
			.thenTrue();
	}

	static function initSaveConfigToRedis(injector :Injector) :Promise<Bool>
	{
		updateStatus(ServerStartupState.SavingConfigToRedis);
		var redis :RedisClient = injector.getValue(RedisClient);
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

	static function initPublicAddress(injector :Injector) :Promise<Bool>
	{
		return Promise.promise(true);
		
		// var redis :RedisClient = injector.getValue(RedisClient);
		// return Promise.promise(true)
		// 	.pipe(function(_) {
		// 		return WorkerProviderTools.getPrivateHostName(config.providers[0])
		// 			.then(function(hostname) {
		// 				Constants.SERVER_HOSTNAME_PRIVATE = hostname;
		// 				// Log.debug({server_status:status, SERVER_HOSTNAME_PRIVATE:Constants.SERVER_HOSTNAME_PRIVATE});
		// 				return true;
		// 			});
		// 	})
		// 	.pipe(function(_) {
		// 		return WorkerProviderTools.getPublicHostName(config.providers[0])
		// 			.then(function(hostname) {
		// 				Constants.SERVER_HOSTNAME_PUBLIC = hostname;
		// 				// Log.debug({server_status:status, SERVER_HOSTNAME_PUBLIC:Constants.SERVER_HOSTNAME_PUBLIC});
		// 				return true;
		// 			});
		// 	});
	}

	static function initStorage(injector :Injector)
	{
		updateStatus(ServerStartupState.CreateStorageDriver);
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

	static function initJobProcessors(injector :Injector) :Promise<Bool>
	{
		var processQueue = new ccc.compute.server.execution.singleworker.ProcessQueue();
		injector.map(ccc.compute.server.execution.singleworker.ProcessQueue).toValue(processQueue);
		injector.injectInto(processQueue);
		return processQueue.ready;
	}

	static function runServer(injector :Injector)
	{
		Constants.DOCKER_CONTAINER_ID = DockerTools.getContainerId();

		var env :DynamicAccess<String> = Node.process.env;

		if (env['DEV'] != "true") {
			Log.info({start:'CCC server start', version: ServerCommands.version()});
		}

		var config :ServiceConfiguration = injector.getValue('ccc.compute.shared.ServiceConfiguration');

		createHttpServer(injector);

		Promise.promise(true)
			.pipe(function(_) {
				return DockerTools.getThisContainerName()
					.then(function(containerName) {
						Constants.DOCKER_CONTAINER_NAME = containerName;
						return true;
					});
			})
			.pipe(function(_) {
				return initRedis(injector);
			})
			.pipe(function(_) {
				return initSaveConfigToRedis(injector);
			})
			//Get public/private network addresses
			.pipe(function(_) {
				return initPublicAddress(injector);
			})
			.then(function(_) {
				var redis :RedisClient = injector.getValue(RedisClient);
				var jobStateTools :JobStateTools = redis;
				StatusStream = jobStateTools.getStatusStream(); //RedisTools.createJsonStream(injector.getValue(RedisClient), ComputeQueue.REDIS_CHANNEL_STATUS);
				injector.map("promhx.Stream<ccc.compute.shared.JobStatusUpdate>", "StatusStream").toValue(StatusStream);
				StatusStream.catchError(function(err) {
					Log.error(err);
				});
			})
			.pipe(function(_) {
				return ccc.compute.server.scaling.WorkerController.init(injector);
			})
			.pipe(function(_) {
				updateStatus(ServerStartupState.BuildingServices);
				return initJobProcessors(injector);
			})
			.then(function(_) {

				var redis :RedisClient = injector.getValue(RedisClient);

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
				ccc.compute.server.scaling.ShutdownController.init(injector);
				ccc.compute.server.scaling.ScalingController.init(injector);
			})
			.pipe(function(_) {
				return postInitSetup(injector);
			})
			.then(function(_) {
				updateStatus(ServerStartupState.Ready);
				if (Node.process.send != null) {//If spawned via a parent process, send will be defined
					Node.process.send(Constants.IPC_MESSAGE_READY);
				}
				return true;
			})
			.then(function(_) {
				runFunctionalTests(injector);
			})
			;
	}

	static function postInitSetup(injector :Injector) :Promise<Bool>
	{
		var env :DynamicAccess<String> = Node.process.env;
		var isRemoveJobs = env[ENV_REMOVE_JOBS_ON_STARTUP] + '' == 'true' || env[ENV_REMOVE_JOBS_ON_STARTUP] == '1';
		if (isRemoveJobs) {
			var service = injector.getValue(ccc.compute.server.execution.routes.RpcRoutes);
			return service.deleteAllJobs()
				.then(function(result) {
					Log.info(result);
					return true;
				});
		} else {
			return Promise.promise(true);
		}
	}

	static function runFunctionalTests(injector :Injector)
	{
		var env :DynamicAccess<String> = Node.process.env;
		//Run internal tests
		var isTravisBuild = env[ENV_TRAVIS] + '' == 'true' || env[ENV_TRAVIS] == '1';
		var disableStartTest = env[ENV_DISABLE_STARTUP_TEST] + '' == 'true' || env[ENV_DISABLE_STARTUP_TEST] == '1';
		if (!disableStartTest) {
			Log.debug('Running server functional tests');
			promhx.RequestPromises.get('http://localhost:${SERVER_DEFAULT_PORT}${SERVER_RPC_URL}/server-tests?${isTravisBuild ? "core=true&storage=true&dockervolumes=true&compute=true&jobs=true&turbojobs=true" : "compute=true&turbojobs=true"}')
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

	static function initStaticFileServing(injector :Injector)
	{
		var app = injector.getValue(Application);

		//Serve metapages dashboards
		app.use('/', Express.Static('./web'));
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

	static function initWebsocketServer(injector :Injector)
	{
		updateStatus(ServerStartupState.StartWebsocketServer);
		var redis :RedisClient = injector.getValue(RedisClient);
		var storage :ServiceStorage = injector.getValue(ServiceStorage);
		var server :js.node.http.Server = injector.getValue(js.node.http.Server, 'Server1');
		var serverHTTP :js.node.http.Server = injector.getValue(js.node.http.Server, 'Server2');
		//Websocket server for getting job finished notifications
		websocketServer(injector.getValue(RedisClient), server, storage);
		websocketServer(injector.getValue(RedisClient), serverHTTP, storage);
	}

	static function websocketServer(redis :RedisClient, server :js.node.http.Server, storage :ServiceStorage) :Void
	{
		var wss = new WebSocketServer({server:server});
		var map = new Map<JobId, WebSocket>();
		var jobStateTools :JobStateTools = redis;
		var jobs :Jobs = redis;

		function notifyJobFinished(jobId :JobId) {
			if (map.exists(jobId)) {
				jobs.getJob(jobId)
					.then(function(job) {
						var resultsPath = job.resultJsonPath();
						storage.readFile(resultsPath)
							.pipe(function(stream) {
								return promhx.StreamPromises.streamToString(stream);
							})
							.then(function(out) {
								var ws = map.get(jobId);
								if (ws != null) {
									var outputJson :JobResult = Json.parse(out);
									ws.send(Json.stringify({jsonrpc:JsonRpcConstants.JSONRPC_VERSION_2, result:outputJson}));
								}
							})
							.catchError(function(err) {
								Log.error({error:err, message:'websocketServer.notifyJobFinished Failed to read file jobId=$jobId resultsPath=$resultsPath'});
							});
					})
					.catchError(function(err) {
						Log.error({error:err, message:'websocketServer.notifyJobFinished Failed to get job for jobId=$jobId'});
					});
			}
		}

		//Listen to websocket connections. After a client submits a job the server
		//returns a JobId. The client then establishes a websocket connection with
		//the jobid so it can listen to job status updates. When the job is finished
		//the job result JSON object is sent back on the websocket.
		wss.on(WebSocketServerEvent.Connection, function(ws) {
			// var location = js.node.Url.parse(ws.upgradeReq['url'], true);
			// you might use location.query.access_token to authenticate or share sessions
			// or ws.upgradeReq.headers.cookie (see http://stackoverflow.com/a/16395220/151312)
			var jobId = null;
			ws.on(WebSocketEvent.Message, function(message :Dynamic, flags) {
				try {
					var jsonrpc :RequestDefTyped<{jobId:String}> = Json.parse(message + '');
					if (jsonrpc.method == Constants.RPC_METHOD_JOB_NOTIFY) {
						//Here is where the interesting stuff happens
						if (jsonrpc.params == null) {
							ws.send(Json.stringify({jsonrpc:JsonRpcConstants.JSONRPC_VERSION_2, error:'Missing params', code:JsonRpcErrorCode.InvalidParams, data:{original_request:jsonrpc}}));
							return;
						}
						var jobId = jsonrpc.params.jobId;
						if (jobId == null) {
							ws.send(Json.stringify({jsonrpc:JsonRpcConstants.JSONRPC_VERSION_2, error:'Missing jobId parameter', code:JsonRpcErrorCode.InvalidParams, data:{original_request:jsonrpc}}));
							return;
						}
						map.set(jobId, ws);
						//Check if job is finished
						jobStateTools.getStatus(jobId)
							.then(function(status :JobStatus) {
								switch(status) {
									case Pending:
									case Working:
									case Finished:
										notifyJobFinished(jobId);
									default:
										Log.error('ERROR no status found for $jobId. Getting the job record and assuming it is finished');
										notifyJobFinished(jobId);
								}
							});

					} else {
						Log.error('Unknown method');
						ws.send(Json.stringify({jsonrpc:JsonRpcConstants.JSONRPC_VERSION_2, error:'Unknown method', code:JsonRpcErrorCode.MethodNotFound, data:{original_request:jsonrpc}}));
					}
				} catch (err :Dynamic) {
					Log.error({error:err});
					ws.send(Json.stringify({jsonrpc:JsonRpcConstants.JSONRPC_VERSION_2, error:'Error parsing JSON-RPC', code:JsonRpcErrorCode.ParseError, data:{original_request:message, error:err}}));
				}
			});
			ws.on(WebSocketEvent.Close, function(code, message) {
				if (jobId != null) {
					map.remove(jobId);
				}
			});
		});

		StatusStream
			.then(function(state :JobStatusUpdate) {
				if (state.jobId == null) {
					Log.warn('No jobId for status=${Json.stringify(state)}');
					return;
				}
				if (map.exists(state.jobId)) {
					switch(state.status) {
						case Pending, Working:
						case Finished:
							notifyJobFinished(state.jobId);
					}
				}
			});
	}

	static function mapEnvVars(injector :Injector)
	{
		var env :DynamicAccess<String> = Node.process.env;
		var redisHost = env[ENV_REDIS_HOST];
		if (redisHost == null || redisHost == '') {
			redisHost = 'redis';
		}
		redisHost = redisHost.replace(':', '');
		var redisPort = env[ENV_REDIS_PORT] != null && env[ENV_REDIS_PORT] != '' ? Std.parseInt(env[ENV_REDIS_PORT]) : REDIS_PORT;
		injector.map(String, ENV_REDIS_HOST).toValue(redisHost);
		injector.map(Int, ENV_REDIS_PORT).toValue(redisPort);
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
