package ccc.compute.server;

import ccc.storage.StorageSourceType;
import haxe.Json;
import haxe.remoting.JsonRpc;

import js.Node;
import js.node.Fs;
import js.node.Path;
import js.node.http.*;
import js.node.Http;
import js.node.Url;
import js.npm.RedisClient;
import js.npm.Docker;
import js.npm.Express;
import js.npm.express.BodyParser;
import js.npm.JsonRpcExpressTools;
import js.npm.Ws;
import js.npm.RedisClient;

import minject.Injector;

import promhx.Promise;

import ccc.compute.InitConfigTools;
import ccc.compute.ComputeQueue;
import ccc.compute.ServiceBatchCompute;
import ccc.compute.execution.Job;
import ccc.compute.execution.Jobs;
import ccc.compute.ConnectionToolsDocker;
import ccc.compute.ConnectionToolsRedis;
import ccc.compute.workers.WorkerProvider;
import ccc.compute.workers.WorkerProviderBoot2Docker;
import ccc.compute.workers.WorkerProviderVagrant;
import ccc.compute.workers.WorkerProviderPkgCloud;
import ccc.compute.workers.WorkerProviderTools;
import ccc.compute.workers.WorkerManager;
import ccc.storage.StorageTools;
import ccc.storage.StorageDefinition;
import ccc.storage.ServiceStorage;
import ccc.storage.StorageRestApi;
import ccc.storage.ServiceStorageLocalFileSystem;

import util.RedisTools;
import util.DockerTools;

using Lambda;
using ccc.compute.JobTools;
using promhx.PromiseTools;

@:enum
abstract ServerStatus(String) {
	var Booting_1_4 = "Booting_1_4";
	var ConnectingToRedis_2_4 = "ConnectingToRedis_2_4";
	var BuildingServices_3_4 = "BuildingServices_3_4";
	var Ready_4_4 = "Ready_4_4";
}

/**
 * Represents a queue of compute jobs in Redis
 * Lots of ideas taken from http://blogs.bronto.com/engineering/reliable-queueing-in-redis-part-1/
 */
class ServerCompute
{
	static function main()
	{
		var v = 'sdfsdfsdsdf';
		//Required for source mapping
		js.npm.SourceMapSupport;
		//Embed various files
		util.EmbedMacros.embedFiles('etc');
		ErrorToJson;
		runServer();
	}

	static function maintest()
	{
		js.npm.SourceMapSupport;
		ErrorToJson;
		Logger.log = new AbstractLogger({name: "ccc", host:""});
		ConnectionToolsRedis.getRedisClient()
			.then(function(redis) {
				Log.info('Connected to redis');
				//Actually create the server and start listening
				var app = new Express();
				var server = Http.createServer(cast app);

				Node.process.on('SIGINT', function() {
					Log.warn("Caught interrupt signal");
					untyped server.close();
					Node.process.exit(0);
				});

				var env = Node.process.env;
				var PORT :Int = Reflect.hasField(env, 'PORT') ? Std.int(Reflect.field(env, 'PORT')) : 9000;
				server.listen(PORT, function() {
					Log.info('Listening http://localhost:$PORT');
				});
			});
	}

	static function runServer()
	{
		js.Node.process.stdout.setMaxListeners(100);
		js.Node.process.stderr.setMaxListeners(100);

		Logger.log = new AbstractLogger({name: APP_NAME_COMPACT});
		haxe.Log.trace = function(v :Dynamic, ?infos : haxe.PosInfos ) :Void {
			Log.trace(v, infos);
		}

		trace({log_check:'haxe_trace'});
		trace('trace_without_objectifying');
		Log.trace({log_check:'trace'});
		Log.trace('trace');
		Log.debug({log_check:'debug'});
		Log.debug('debug');
		Log.info({log_check:'info'});
		Log.info('info');
		Log.warn({log_check:'warn'});
		Log.error({log_check:'error'});

		var env = Node.process.env;

		//Sanity checks
		if (ConnectionToolsDocker.isInsideContainer() && !ConnectionToolsDocker.isLocalDockerHost()) {
			Log.critical('/var/run/docker.sock is not mounted and the server is in a container. How does the server call docker commands?');
			js.Node.process.exit(-1);
		}

		var CONFIG_PATH :String = Reflect.hasField(env, 'CONFIG_PATH') ? Reflect.field(env, 'CONFIG_PATH') : SERVER_MOUNTED_CONFIG_FILE;
		Log.debug({'CONFIG_PATH':CONFIG_PATH});
		var config :ServiceConfiguration = InitConfigTools.ohGodGetConfigFromSomewhere(CONFIG_PATH);
		Assert.notNull(config);
		Log.info({server_status:ServerStatus.Booting_1_4, config:config, config_path:CONFIG_PATH, HOST_PWD:Node.process.env['HOST_PWD']});

		var status = ServerStatus.Booting_1_4;
		var injector = new Injector();
		injector.map(Injector).toValue(injector); //Map itself

		injector.map('ServiceConfiguration').toValue(config);

		if (config.providers == null) {
			throw 'config.workerProviders == null';
		}

		Assert.notNull(config.server);
		var storageConfig = StorageTools.getConfigFromServiceConfiguration(config);
		injector.map('ccc.storage.StorageDefinition').toValue(storageConfig);

		var ROOT = Path.dirname(Path.dirname(Path.dirname(Node.__dirname)));

		var app = new Express();
		injector.map(Express).toValue(app);

		untyped __js__('app.use(require("cors")())');
		//Just log everything while I'm debugging/testing
#if debug
		app.all('*', cast function(req, res, next) {
			trace(req.url);
			next();
		});
#end

		app.use(untyped Node.require('express-bunyan-logger').errorLogger());

		app.get('/version', function(req, res) {
			var haxeCompilerVersion = Version.getHaxeCompilerVersion();
			var customVersion = null;
			try {
				customVersion = Fs.readFileSync(Path.join(ROOT, 'VERSION'), {encoding:'utf8'});
			} catch(ignored :Dynamic) {
				customVersion = 'Missing VERSION file';
			}
			res.send(Json.stringify({compiler:haxeCompilerVersion, file:customVersion, status:status}));
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
		app.get(Constants.SERVER_PATH_READY, cast function(req, res) {
			if (status == ServerStatus.Ready_4_4) {
				Log.debug('${Constants.SERVER_PATH_READY}=YES');
				res.status(200).end();
			} else {
				Log.debug('${Constants.SERVER_PATH_READY}=NO');
				res.status(500).end();
			}
		});

		//Check if server is ready
		app.get(Constants.SERVER_PATH_WAIT, cast function(req, res) {
			function check() {
				if (status == ServerStatus.Ready_4_4) {
					res.status(200).end();
					return true;
				} else {
					return false;
				}
			}
			var poll;
			poll = function() {
				if (!check()) {
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

		status = ServerStatus.ConnectingToRedis_2_4;
		Log.info({server_status:status});
		Promise.promise(true)
			.pipe(function(_) {
				return ConnectionToolsRedis.getRedisClient()
					.pipe(function(redis) {
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
				var storage :ServiceStorage = StorageTools.getStorage(storageConfig);
				Assert.notNull(storage);
				injector.map(ServiceStorage).toValue(storage);

				var workerProviders = config.providers.map(WorkerProviderTools.getProvider);

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

				//Actually create the server and start listening
				var server = Http.createServer(cast app);
				var serverHTTP = Http.createServer(cast app);

				//Websocket server for getting job finished notifications
				websocketServer(injector.getValue(RedisClient), server, storage);
				websocketServer(injector.getValue(RedisClient), serverHTTP, storage);


				//After all API routes, assume that any remaining requests are for files.
				//This is nice for local development
				if (storageConfig.type == StorageSourceType.Local) {
					// Show a nice browser for the local file system.
					Log.debug('Setting up static file server for output from Local Storage System at: ${config.server.storage.rootPath}');
					app.use('/', Node.require('serve-index')(config.server.storage.rootPath, {'icons': true}));
				}
				//Setup a static file server to serve job results
				app.use('/', StorageRestApi.staticFileRouter(storage));

				var closing = false;
				Node.process.on('SIGINT', function() {
					Log.warn("Caught interrupt signal");
					if (closing) {
						return;
					}
					closing = true;
					untyped server.close(function() {
						untyped serverHTTP.close(function() {
							return Promise.whenAll(workerProviders.map(function(workerProvider) {
								return workerProvider.dispose();
							}))
							.then(function(_) {
								Node.process.exit(0);
							});
						});
					});
				});

				var PORT :Int = Reflect.hasField(env, 'PORT') ? Std.int(Reflect.field(env, 'PORT')) : 9000;
				server.listen(PORT, function() {
					Log.info('Listening http://localhost:$PORT');
					serverHTTP.listen(SERVER_HTTP_PORT, function() {
						Log.info('Listening http://localhost:$SERVER_HTTP_PORT');
						status = ServerStatus.Ready_4_4;
						Log.debug({server_status:status});
						if (Node.process.send != null) {//If spawned via a parent process, send will be defined
							Node.process.send(Constants.IPC_MESSAGE_READY);
						}

						// var disableServerCheck :Dynamic = Reflect.field(env, ENV_DISABLE_SERVER_CHECKS);
						// if (!(disableServerCheck != null && (disableServerCheck == '1' || disableServerCheck == 'true' || disableServerCheck == 'True'))) {
						// 	ccc.compute.server.tests.TestServerAPI.runServerAPITests()
						// 		.then(function(success) {
						// 			if (!success) {
						// 				Log.critical('Failed functional tests');
						// 				Node.process.exit(1);
						// 			}
						// 		})
						// 		.catchError(function(err) {
						// 			Log.critical({message:'Error in functional tests', error:err});
						// 			Node.process.exit(1);
						// 		});
						// }
					});
				});
			});
	}

	static function websocketServer(redis :RedisClient, server :Server, storage :ServiceStorage) :Void
	{
		var wss = new WebSocketServer({server:server});
		var map = new Map<JobId, WebSocket>();

		function notifyJobFinished(jobId :JobId, status :JobStatusUpdate, job :DockerJobDefinition) {
			if (map.exists(jobId)) {
				var ws = map.get(jobId);
				var resultsPath = job.resultJsonPath();
				storage.readFile(resultsPath)
					.pipe(function(stream) {
						return promhx.StreamPromises.streamToString(stream);
					})
					.then(function(out) {
						var outputJson :JobResult = Json.parse(out);
						ws.send(Json.stringify({jsonrpc:'2.0', result:outputJson}));
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
							ws.send(Json.stringify({jsonrpc:'2.0', error:'Missing params', code:JsonRpcErrorCode.InvalidParams, data:{original_request:jsonrpc}}));
							return;
						}
						var jobId = jsonrpc.params.jobId;
						if (jobId == null) {
							ws.send(Json.stringify({jsonrpc:'2.0', error:'Missing jobId parameter', code:JsonRpcErrorCode.InvalidParams, data:{original_request:jsonrpc}}));
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
						ws.send(Json.stringify({jsonrpc:'2.0', error:'Unknown method', code:JsonRpcErrorCode.MethodNotFound, data:{original_request:jsonrpc}}));
					}
				} catch (err :Dynamic) {
					Log.error(err);
					ws.send(Json.stringify({jsonrpc:'2.0', error:'Error parsing JSON-RPC', code:JsonRpcErrorCode.ParseError, data:{original_request:message, error:err}}));
				}
			});
			ws.on(WebSocketEvent.Close, function(code, message) {
				if (jobId != null) {
					map.remove(jobId);
				}
			});
		});

		var stream = RedisTools.createJsonStream(redis, ComputeQueue.REDIS_CHANNEL_STATUS)//, ComputeQueue.REDIS_KEY_STATUS)
		// var stream = RedisTools.createPublishStream(redis, ComputeQueue.REDIS_CHANNEL_STATUS)
			.then(function(status :JobStatusUpdate) {
				// var status :JobStatusObj = Json.parse(out);
				if (status.jobId == null) {
					Log.warn('No jobId for status=${Json.stringify(status)}');
					return;
				}
				if (map.exists(status.jobId)) {
					switch(status.JobStatus) {
						case Pending, Working, Finalizing:
							trace('job=${status.jobId} status=${status.JobStatus}');
						case Finished:
							notifyJobFinished(status.jobId, status, status.job);
					}
				} else {
					trace('but no websocket open');
				}
			});
		stream.catchError(function(err) {
			Log.error(err);
		});
	}
}
