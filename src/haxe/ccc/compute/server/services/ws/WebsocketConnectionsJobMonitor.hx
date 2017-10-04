package ccc.compute.server.services.ws;

import haxe.remoting.JsonRpc;

import js.npm.ws.WebSocket;

class WebsocketConnectionsJobMonitor
{
	public function handleWebsocketConnection(ws :WebSocket)
	{
		// //Listen to websocket connections. After a client submits a job the server
		// //returns a JobId. The client then establishes a websocket connection with
		// //the jobid so it can listen to job status updates. When the job is finished
		// //the job result JSON object is sent back on the websocket.
		// wss.on(WebSocketServerEvent.Connection, function(ws) {
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
					_map.set(jobId, ws);
					//Check if job is finished
					JobStateTools.getStatus(jobId)
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
				_map.remove(jobId);
			}
		});
	}

	function notifyJobFinished(jobId :JobId)
	{
		if (_map.exists(jobId)) {
			Jobs.getJob(jobId)
				.then(function(job) {
					var resultsPath = job.resultJsonPath();
					_storage.readFile(resultsPath)
						.pipe(function(stream) {
							return promhx.StreamPromises.streamToString(stream);
						})
						.then(function(out) {
							var ws = _map.get(jobId);
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

	@post
	public function postInject()
	{
		_StatusStream = JobStream.getStatusStream();

		_StatusStream
			.then(function(state :JobStatsData) {
				if (state != null) {
					if (state.jobId == null) {
						Log.warn('No jobId for status=${Json.stringify(state)}');
						return;
					}
					switch(state.status) {
						case Pending, Working:
						case Finished:
							notifyJobFinished(state.jobId);
					}
				}
			});
	}

	public function new() {}

	var _map :Map<JobId, WebSocket> = new Map();
	var _StatusStream :Stream<JobStatsData>;

	@inject public var _redis: ServerRedisClient;
	@inject public var _storage :ServiceStorage;
}