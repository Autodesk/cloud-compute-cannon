package ccc.compute.server;

import haxe.remoting.JsonRpc;
import haxe.DynamicAccess;

import js.Error;
import js.Node;
import js.node.Fs;
import js.node.Path;
import js.node.Process;
import js.node.http.*;
import js.node.Http;
import js.node.Url;
import js.node.stream.Readable;
import js.npm.RedisClient;
import js.npm.docker.Docker;
import js.npm.Express;
import js.npm.express.BodyParser;
import js.npm.JsonRpcExpressTools;
import js.npm.Ws;
import js.npm.RedisClient;

import minject.Injector;

import ccc.compute.server.InitConfigTools;
import ccc.compute.server.ComputeQueue;
import ccc.compute.server.ServiceBatchCompute;
import ccc.compute.execution.Job;
import ccc.compute.execution.Jobs;
import ccc.compute.server.ConnectionToolsDocker;
import ccc.compute.server.ConnectionToolsRedis;
import ccc.compute.workers.WorkerProvider;
import ccc.compute.workers.WorkerProviderBoot2Docker;
import ccc.compute.workers.WorkerProviderVagrant;
import ccc.compute.workers.WorkerProviderPkgCloud;
import ccc.compute.workers.WorkerProviderTools;
import ccc.compute.workers.WorkerManager;
import ccc.storage.StorageSourceType;
import ccc.storage.StorageTools;
import ccc.storage.StorageDefinition;
import ccc.storage.ServiceStorage;
import ccc.storage.StorageRestApi;
import ccc.storage.ServiceStorageLocalFileSystem;

import promhx.Stream;

import util.RedisTools;
import util.DockerTools;

using Lambda;
using ccc.compute.server.JobTools;
using promhx.PromiseTools;

@:enum
abstract ServerStatus(String) {
	var Booting_1_5 = "Booting_1_5";
	var ConnectingToRedis_2_5 = "ConnectingToRedis_2_5";
	var BuildingServices_3_5 = "BuildingServices_3_5";
	var InitializingProvider_4_5 = "InitializingProvider_4_5";
	var Ready_5_5 = "Ready_5_5";
}

/**
 * Represents a queue of compute jobs in Redis
 * Lots of ideas taken from http://blogs.bronto.com/engineering/reliable-queueing-in-redis-part-1/
 */
class ServerCompute
{
	public static var StorageService :ServiceStorage;
	public static var WorkerProvider :WorkerProvider;
	public static var StatusStream :Stream<JobStatusUpdate>;

	static function main()
	{
		//Required for source mapping
		js.npm.sourcemapsupport.SourceMapSupport;
		//Embed various files
		util.EmbedMacros.embedFiles('etc', ["etc/hxml/.*"]);
		ErrorToJson;
		monitorMemory();
		runServer();
	}

	static function runServer()
	{
		js.Node.process.stdout.setMaxListeners(100);
		js.Node.process.stderr.setMaxListeners(100);

		Constants.DOCKER_CONTAINER_ID = DockerTools.getContainerId();

		//Load env vars from an .env file if present
		Node.require('dotenv').config({path: '.env', silent: true});
		Node.require('dotenv').config({path: 'config/.env', silent: true});

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
			Log.info('GLOBAL_LOG_LEVEL=${Logger.GLOBAL_LOG_LEVEL}');
		}

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
					ccc.compute.server.FluentTools.logToFluent(Json.stringify(errObj), function() {
						Node.process.exit(1);
					});
				} else {
					Node.process.exit(1);
				}
			} catch(e :Dynamic) {
				Node.process.exit(1);
			}
		});

		//Sanity checks
		if (util.DockerTools.isInsideContainer() && !ConnectionToolsDocker.isLocalDockerHost()) {
			Log.critical('/var/run/docker.sock is not mounted and the server is in a container. How does the server call docker commands?');
			js.Node.process.exit(-1);
		}

		var config :ServiceConfiguration = InitConfigTools.getConfig();

		Assert.notNull(config);
		var CONFIG_PATH :String = Reflect.hasField(env, ENV_VAR_COMPUTE_CONFIG_PATH) && Reflect.field(env, ENV_VAR_COMPUTE_CONFIG_PATH) != "" ? Reflect.field(env, ENV_VAR_COMPUTE_CONFIG_PATH) : SERVER_MOUNTED_CONFIG_FILE_DEFAULT;
		Log.info({server_status:ServerStatus.Booting_1_5, config:LogTools.removePrivateKeys(config), config_path:CONFIG_PATH, HOST_PWD:env['HOST_PWD']});

		var status = ServerStatus.Booting_1_5;
		var injector = new Injector();
		injector.map(Injector).toValue(injector); //Map itself

		for (key in Reflect.fields(config)) {
			if (key != 'storage' && key != 'providers') {
				Reflect.setField(env, key, Reflect.field(config, key));
			}
		}

		Log.info({start:'CCC server start', version: ServerCommands.version()});

		Log.trace({log_check:'trace'});
		Log.trace('trace');
		Log.debug({log_check:'debug'});
		Log.debug('debug');
		Log.info({log_check:'info'});
		Log.info('info');
		Log.warn({log_check:'warn'});
		Log.error({log_check:'error'});

		injector.map('ServiceConfiguration').toValue(config);

		if (config.providers == null) {
			throw 'config.providers == null';
		}

		/* Storage*/
		Assert.notNull(config.storage);
		var storageConfig :StorageDefinition = config.storage;
		var storage :ServiceStorage = StorageTools.getStorage(storageConfig);
		Assert.notNull(storage);
		StorageService = storage;
		injector.map('ccc.storage.StorageDefinition').toValue(storageConfig);
		injector.map(ccc.storage.ServiceStorage).toValue(storage);

		var ROOT = Path.dirname(Path.dirname(Path.dirname(Node.__dirname)));

		var app = new Express();
		injector.map(Express).toValue(app);

		untyped __js__('app.use(require("cors")())');

		app.get('/version', function(req, res) {
			var versionBlob = ServerCommands.version();
			res.send(versionBlob.VERSION);
		});

		app.get('/version_extra', function(req, res) {
			var versionBlob = ServerCommands.version();
			res.send(Json.stringify(versionBlob));
		});

		app.get('/config', function(req, res) {
			var configCopy = LogTools.removePrivateKeys(config);
			res.send(Json.stringify(configCopy, null, '  '));
		});

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
			if (status == ServerStatus.Ready_5_5) {
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
				if (status == ServerStatus.Ready_5_5) {
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

		status = ServerStatus.ConnectingToRedis_2_5;
		Log.info({server_status:status});

		var workerProviders :Array<ccc.compute.workers.WorkerProvider> = [];

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

		var closing = false;
		Node.process.on('SIGINT', function() {
			Log.warn("Caught interrupt signal");
			if (closing) {
				return;
			}
			closing = true;
			untyped server.close(function() {
				untyped serverHTTP.close(function() {
					if (workerProviders != null) {
						return Promise.whenAll(workerProviders.map(function(workerProvider) {
							return workerProvider.dispose();
						}))
						.then(function(_) {
							Node.process.exit(0);
							return true;
						});
					} else {
						Node.process.exit(0);
						return Promise.promise(true);
					}
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

		Promise.promise(true)
			.pipe(function(_) {
				return DockerTools.getThisContainerName()
					.then(function(containerName) {
						Constants.DOCKER_CONTAINER_NAME = containerName;
						return true;
					});
			})
			.pipe(function(_) {
				return ConnectionToolsRedis.getRedisClient()
					.pipe(function(redis) {
						//Pipe specific logs from redis since while developing
						// ServiceBatchComputeTools.pipeRedisLogs(redis);
						injector.map(RedisClient).toValue(redis);

						if (Reflect.field(env, ENV_CLEAR_DB_ON_START) == 'true') {
							Log.warn('Deleting all keys prior to starting stack');
							return ComputeQueue.deleteAllKeys(redis)
								.pipe(function(_) {
									return InstancePool.deleteAllKeys(redis);
								})
								.then(function(_) {
									return redis;
								});
						} else {
							return Promise.promise(redis);
						}
					})
					.pipe(function(redis) {
						return InitConfigTools.initAll(redis);
					});
			})
			.pipe(function(_) {
				//Print the status of the workers before doing anything
				var redis :RedisClient = injector.getValue(RedisClient);

				function pollWorkers() {
					return ccc.compute.server.ServerCommands.statusWorkers(redis)
						.then(function(data) {
							Log.debug({message:'Workers', workers:data});
							return true;
						})
						.errorPipe(function(err) {
							Log.error('Failed to get worker status err=${Json.stringify(err)}');
							return Promise.promise(true);
						});
				}

				var fiveMinutes = 5*60*1000;
				Node.setInterval(function() {
					pollWorkers();
				}, fiveMinutes);

				return pollWorkers();
			})
			//Get public/private network addresses
			.pipe(function(_) {
				var redis :RedisClient = injector.getValue(RedisClient);
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
			.pipe(function(_) {
				status = ServerStatus.BuildingServices_3_5;
				Log.debug({server_status:status});

				//Build and inject the app logic
				//Create services
				workerProviders = config.providers.map(WorkerProviderTools.getProvider);
				WorkerProvider = workerProviders[0];
				injector.map(ccc.compute.workers.WorkerProvider).toValue(WorkerProvider);
				injector.injectInto(WorkerProvider);
				return WorkerProvider.ready;
			})
			.then(function(_) {
				//The queue manager
				var schedulingService = new ccc.compute.server.ServiceBatchCompute();
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

				//RPC machinery
				//Server infrastructure. This automatically handles client JSON-RPC remoting and other API requests
				app.use(SERVER_API_URL, cast schedulingService.router());

				StatusStream = RedisTools.createJsonStream(injector.getValue(RedisClient), ComputeQueue.REDIS_CHANNEL_STATUS);
				StatusStream.catchError(function(err) {
					Log.error(err);
				});

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

				status = ServerStatus.Ready_5_5;
				Log.debug({server_status:status});
				if (Node.process.send != null) {//If spawned via a parent process, send will be defined
					Node.process.send(Constants.IPC_MESSAGE_READY);
				}

				//Run internal tests
				Log.debug('Running server functional tests');
				var isTravisBuild = env[ENV_TRAVIS] + '' == 'true' || env[ENV_TRAVIS] == '1';
				promhx.RequestPromises.get('http://localhost:${SERVER_DEFAULT_PORT}${SERVER_RPC_URL}/server-tests?${isTravisBuild ? "core=true&storage=true&dockervolumes=true&compute=true&jobs=true" : "compute=true"}')
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
			});
	}

	static function websocketServer(redis :RedisClient, server :Server, storage :ServiceStorage) :Void
	{
		var wss = new WebSocketServer({server:server});
		var map = new Map<JobId, WebSocket>();

		function notifyJobFinished(jobId :JobId, status :JobStatusUpdate, job :DockerJobDefinition) {
			if (map.exists(jobId)) {
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
						Log.error({error:err, message:'Failed to read file jobId=$jobId resultsPath=$resultsPath', JobStatusUpdate:status});
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
						ComputeQueue.getStatus(redis, jobId)
							.then(function(status :JobStatusUpdate) {
								switch(status.JobStatus) {
									case Pending:
									case Working:
									case Finished:
										notifyJobFinished(jobId, status, null);
									default:
										Log.error('ERROR no status found for $jobId. Getting the job record and assuming it is finished');
										ComputeQueue.getJob(redis, jobId)
											.then(function(jobItem :DockerJobDefinition) {
												notifyJobFinished(jobId, status, jobItem);
											});
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
			.then(function(status :JobStatusUpdate) {
				if (status.jobId == null) {
					Log.warn('No jobId for status=${Json.stringify(status)}');
					return;
				}
				if (map.exists(status.jobId)) {
					switch(status.JobStatus) {
						case Pending, Working, Finalizing:
						case Finished:
							notifyJobFinished(status.jobId, status, status.job);
					}
				}
			});
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
