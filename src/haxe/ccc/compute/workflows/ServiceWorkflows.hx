package ccc.compute.workflows;

import t9.js.jsonrpc.Routes;

import js.node.Http;
import js.node.http.*;
import js.npm.docker.Docker;
import js.npm.busboy.Busboy;
import js.npm.RedisClient;
import js.npm.streamifier.Streamifier;
import js.npm.shortid.ShortId;
import js.npm.fsextended.FsExtended;

import ccc.storage.ServiceStorage;

import util.MultiformTools;

class ServiceWorkflows
{
	@rpc({
		alias:'workflow-result',
		express: '/workflow/result/:workflowId'
	})
	public function getWorkflowResult(workflowId :WorkflowId) :Promise<WorkflowResult>
	{
		return WorkflowTools.getWorkflowResult(_storage, workflowId);
	}

	@rpc({
		alias:'workflow-state',
		express: '/workflow/status/:workflowId'
	})
	public function getWorkflowStatus(workflowId :WorkflowId) :Promise<WorkflowState>
	{
		var redis :WorkflowRedis = _redis;
		return redis.getWorkflowState(workflowId)
			.pipe(function(state :WorkflowState) {
				return switch(state) {
					case Running: Promise.promise(state);
					case None,Finished:
						WorkflowTools.isFinishedWorkflow(_storage, workflowId)
							.then(function(isFinished) {
								return isFinished ? WorkflowState.Finished : WorkflowState.None;
							});
				}
			});
	}

	public function multiFormWorkflowRouter() :IncomingMessage->ServerResponse->(?Dynamic->Void)->Void
	{
		return function(req, res, next) {
			var contentType :String = req.headers['content-type'];
			traceRed(req.url);
			var isMultiPart = contentType != null && contentType.indexOf('multipart/form-data') > -1;
			if (isMultiPart) {
				handleMultiformWorkflowRun(req, res, next);
			} else {
				next();
			}
		}
	}

	public function handleMultiformWorkflowRun(req :IncomingMessage, res :ServerResponse, next :?Dynamic->Void) :Void
	{
		var tempWorkflowPath :String = '/tmp/workflow__${ShortId.generate()}/';
		traceYellow(tempWorkflowPath);
		var returned = false;
		var workflowId :String = null;
		var redis :WorkflowRedis = _redis;

		var queryParams :DynamicAccess<String> = untyped req.query;
		var wait :Bool = queryParams != null && (queryParams.get("wait") == "true" || queryParams.get("wait") == "1");
		var useCache :Bool = !(queryParams != null && queryParams.get("cache") == "false" || queryParams.get("cache") == "0");
		var keepIntermediate :Bool = queryParams != null && (queryParams.get("keep") == "true" || queryParams.get("keep") == "1");

		function cleanup() {
			FsExtended.deleteDir(tempWorkflowPath, function(err) {
				if (err != null) {
					Log.info('Got error deleting $tempWorkflowPath error=${err}');
				}
			});
		}

		function returnError(err :haxe.extern.EitherType<String, js.Error>, ?statusCode :Int = 500) {
			Log.error('err=$err');
			if (returned) return;
			res.writeHead(statusCode, {'content-type': 'application/json'});
			res.end(Json.stringify({error: err}));
			returned = true;
			//Cleanup
			cleanup();
		}

		MultiformTools.pipeFilesToFolder(tempWorkflowPath, req)
			.then(function(files) {
				if (!files.has(WORKFLOW_JSON_FILE)) {
					returnError('Missing "${WORKFLOW_JSON_FILE}" file', 400);
				} else {
					var workflowPath = Path.join(tempWorkflowPath, WORKFLOW_JSON_FILE);
					try {
						var workflow :WorkflowDefinition = Json.parse(FsExtended.readFileSync(workflowPath, {encoding:'utf8'}));
						WorkflowTools.getWorkflowHash(tempWorkflowPath)
							.pipe(function(workflowHash :String) {
								workflowId = workflowHash;
								return WorkflowTools.isFinishedWorkflow(_storage, workflowId);
							})
							.then(function(isFinishedWorkflow :Bool) {
								Log.info('Workflow hashId=$workflowId isFinishedWorkflow=$isFinishedWorkflow useCache=$useCache');
								if (isFinishedWorkflow && useCache) {
									//Just in case this didn't get removed previously
									redis.removeWorkflow(workflowId);
									_storage.readFile(WorkflowTools.getWorkflowResultPath(workflowId))
										.then(function(stream) {
											untyped res.append(WORKFLOW_HTTP_HEADER_CACHE, 'true');
											res.writeHead(200, {'content-type': 'application/json'});
											stream.pipe(res);
										})
										.catchError(function(err) {
											returnError(err);
										});
								} else {
									redis.getWorkflowState(workflowId)
										.then(function(state :WorkflowState) {
											traceCyan('state=$state');
											var alreadyRunning = switch(state) {
												case Running: true;
												case Finished: false;
												case None: false;
											}
											if (alreadyRunning && useCache) {
												Log.info('Workflow $workflowId already running');
												cleanup();
												if (wait) {
													var finishBlob = redis.onWorkflowFinished(workflowId);
													//Make sure the redis listener is closed when this connection
													//is closed
													req.on('close', function() {
														traceCyan('request closed');
														finishBlob.cancel();
													});
													finishBlob.promise
														.then(function(finished) {
															traceRed('Got finished blob promise');
															_storage.readFile(WorkflowTools.getWorkflowResultPath(workflowId))
																.then(function(stream) {
																	untyped res.append(WORKFLOW_HTTP_HEADER_CACHE, 'true');
																	res.writeHead(200, {'content-type': 'application/json'});
																	stream.pipe(res);
																})
																.catchError(function(err) {
																	returnError(err);
																});
														})
														.catchError(function(err) {
															finishBlob.cancel();
															returnError(err);
														});
												} else {
													//If you're not waiting, just return the workflow id
													res.writeHead(200, {'content-type': 'application/json'});
													res.end(Json.stringify({"workflowId":workflowId, state:state, "cache":useCache, "wait":wait}));
													cleanup();
												}

											} else {
												redis.setWorkflowState(workflowId, WorkflowState.Running)
													.pipe(function(_) {
														if (!wait) {
															res.writeHead(200, {'content-type': 'application/json'});
															res.end(Json.stringify({workflowId:workflowId, state:WorkflowState.Running, "cache":useCache, "wait":wait}));
															returned = true;
														}
														Log.info('Running workflow hash=$workflowId');
														return WorkflowTools.runWorkflow(workflowId, _storage, workflow, tempWorkflowPath, !keepIntermediate)
															.pipe(function(result) {
																untyped result.workflowId = workflowId;
																return WorkflowTools.saveWorkflowResult(_storage, workflowId, cast result)
																	.pipe(function(result) {
																		return redis.setWorkflowState(workflowId, WorkflowState.Finished)
																			.then(function(result) {
																				Log.debug('workflow=$workflowId state=${WorkflowState.Finished}');
																				//Remove from redis when finished, but give time for redis to update the channel
																				Node.setTimeout(function() {
																					redis.removeWorkflow(workflowId);
																				}, 1000);
																				return result;
																			});
																	})
																	.then(function(_) {
																		return result;
																	});
															});
													})
													.then(function(result) {
														if (wait) {
															untyped res.append(WORKFLOW_HTTP_HEADER_CACHE, 'false');
															res.writeHead(200, {'content-type': 'application/json'});
															res.end(Json.stringify(result));
															cleanup();
														}
													})
													.catchError(function(err) {
														returnError(err);
													});
											}
									})
									.catchError(function(err) {
										returnError(err);
									});
								}
							})
							.catchError(function(err) {
								traceRed('IN SERVICE ERROR HANDLER');
								returnError(err);
							});

					} catch(err :Dynamic) {
						returnError('Failed to parse json file err=${Json.stringify(err)}', 400);
					}
				}
			})
			.catchError(function(err) {
				returnError(err);
			});
	}

	public function new() {}

	// var redis (get, null):WorkflowRedis;
	// function get_redis() :WorkflowRedis
	// {
	// 	return _redis;
	// }

	@inject public var _redis :RedisClient;
	@inject public var _storage :ServiceStorage;
}