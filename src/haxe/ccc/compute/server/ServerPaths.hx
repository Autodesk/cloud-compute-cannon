package ccc.compute.server;

import ccc.compute.server.execution.routes.ServerCommands;
import ccc.compute.worker.WorkerStateManager;

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

class ServerPaths
{
	public static function initAppPaths(injector :ServerState)
	{
		var app = Express.GetApplication();
		injector.map(Application).toValue(app);

		app.use(Node.require('express-bunyan-logger')());

		var cors = Node.require('cors')();
		app.options('*', cors);
		app.use(cors);

		app.use(cast js.npm.bodyparser.BodyParser.json({limit: '250mb'}));

		//Serve metapages dashboards
		var indexPage = new haxe.Template(sys.io.File.getContent('./web/index-template.html')).execute(ServerConfig);
		app.get('/', function(req, res) {
			res.send(indexPage);
		});

		app.get('/index.* ', function(req, res) {
			res.send(indexPage);
		});

		app.get('/version', function(req, res) {
			var versionBlob = ServerCommands.version();
			res.send(versionBlob.git);
		});

		QueueTools.addBullDashboard(injector);

		function test(req, res) {
			var monitorService = injector.getValue(ServiceMonitorRequest);
			monitorService.monitor(req.query)
				.then(function(result :ServiceMonitorRequestResult) {
					if (result.success) {
						res.json(result);
					} else {
						res.status(500).json(cast result);
					}
				}).catchError(function(err) {
					res.status(500).json(cast {error:err, success:false});
				});
		}

		app.get('/healthcheck', function(req, res :Response) {
			var workerManager = injector.getValue(WorkerStateManager);
			workerManager.registerHealthStatus()
				.then(function(_) {
					res.json(cast {success:true});
				}).catchError(function(err) {
					res.status(500).json(cast {error:err, success:false});
				});
		});

		app.get('/test', function(req, res) {
			test(req, res);
		});

		/**
		 * Used in tests to check for loading URL inputs
		 */
		app.get('/mirrorfile/:content', function(req, res) {
			res.send(req.params.content);
		});

		app.get('/check', function(req, res) {
			test(req, res);
		});

		app.get('/version_extra', function(req, res) {
			var versionBlob = ServerCommands.version();
			res.send(Json.stringify(versionBlob));
		});

		//Check if server is listening
		app.get(Constants.SERVER_PATH_CHECKS, function(req, res) {
			res.send(Constants.SERVER_PATH_CHECKS_OK);
		});
		//Check if server is listening
		app.get(Constants.SERVER_PATH_STATUS, function(req, res) {
			res.send('{"status":"${injector.getStatus()}"}');
		});

		//Check if server is ready
		app.get(SERVER_PATH_READY, cast function(req, res) {
			if (injector.getStatus() == ServerStartupState.Ready) {
				Log.debug('${SERVER_PATH_READY}=YES');
				res.status(200).end();
			} else {
				Log.debug('${SERVER_PATH_READY}=NO');
				res.status(500).end();
			}
		});

		//Check if server is ready
		app.get(SERVER_PATH_WAIT, cast function(req, res) {
			function check() {
				if (injector.getStatus() == ServerStartupState.Ready) {
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
		app.get('/jobcount', function(req, res :Response) {
			if (injector.hasMapping(WorkerStateManager)) {
				var wc :WorkerStateManager = injector.getValue(WorkerStateManager);
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
		app.get('/worker-jobs', function(req, res :Response) {
			if (injector.hasMapping(ServerRedisClient)) {
				Jobs.getAllWorkerJobs()
					.pipe(function(result) {
						return JobStateTools.getJobsWithStatus(JobStatus.Pending)
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

		app.use(cast function(err :js.Error, req, res, next) {
			var errObj = {
				stack: try err.stack catch(e :Dynamic){null;},
				error: err,
				errorJson: try untyped err.toJSON() catch(e :Dynamic){null;},
				errorString: try untyped err.toString() catch(e :Dynamic){null;},
				message: try untyped err.message catch(e :Dynamic){null;},
			}
			Log.error(errObj);
			try {
				traceRed(Json.stringify(errObj, null, '  '));
			} catch(e :Dynamic) {
				traceRed(errObj);
			}
		});
	}
}