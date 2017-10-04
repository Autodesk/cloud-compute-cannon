package ccc.compute.server.services.ws;

import ccc.dashboard.action.*;
import ccc.dashboard.state.*;

import haxe.Serializer;
import haxe.Unserializer;

import js.react.util.WebsocketTools;

import redux.Redux;

import haxe.remoting.JsonRpc;

import js.npm.ws.WebSocket;

class WebsocketConnectionDashboard
{
	@inject('StatusStream') public var _JOB_STREAM :Stream<JobStatsData>;
	@inject('ActiveJobStream') public var _ACTIVE_JOB_STREAM :Stream<Array<JobId>>;
	@inject('FinishedJobStream') public var _FINISHED_JOB_STREAM :Stream<Array<JobId>>;

	var _ws :WebSocket;
	var _stream :Stream<Void>;
	var _activeJobStream :Stream<Void>;
	var _finishedJobStream :Stream<Void>;

	public function new(ws :WebSocket)
	{
		Assert.that(ws != null);
		_ws = ws;
		_ws.onmessage = onMessage;
		_ws.onclose = onClose;
	}

	function onMessage(message :Dynamic, flags :Dynamic)
	{
		switch(WebsocketTools.decodeMessage(message)) {
			case ActionMessage(action):
				switch(action.type) {
					case 'ccc.dashboard.action.DashboardAction':
						//Ignore all these, they do not come from the server
						var en :DashboardAction = cast action.value;
					case 'ccc.dashboard.action.WebsocketAction':
					default: throw 'Unknown action ${action}';
				}
			case JsonMessage(obj):
				Log.error('Unhandled websocket JSON message=${Json.stringify(obj)}');
			case Unknown(unknown):
				Log.error('Error unknown websocket message=$message');
			case DecodingWebsocketError(error, message):
				Log.error('Error decoding websocket message=$message error=$error');
				if (_ws != null) {
					sendMessage(WebsocketAction.ServerError('Error processing action message=${message} err=${error}', null));
				}
		}
	}

	function onClose(code :Int, message :Dynamic)
	{
		if (_ws != null) {
			_ws.onmessage = null;
			_ws.onclose = null;
			_ws = null;
		}
		if (_stream != null) {
			_stream.end();
			_stream = null;
		}

		if (_activeJobStream != null) {
			_activeJobStream.end();
			_activeJobStream = null;
		}

		if (_finishedJobStream != null) {
			_finishedJobStream.end();
			_finishedJobStream = null;
		}

		_JOB_STREAM = null;
		_activeJobStream = null;
		_finishedJobStream = null;
	}

	function sendMessage(e :EnumValue)
	{
		sendMessageString(WebsocketTools.encodeEnum(e));
	}

	/**
	 * Prefer sendMessage for type checking, but this can be faster
	 * than repeatedly serializing the same message
	 */
	function sendMessageString(m :String)
	{
		if (_ws != null) {
			_ws.send(m);
		} else {
			Log.error('Cannot send action=${m} because WS connection is disposed.');
		}
	}

	@post
	public function postInject()
	{
		JobStatsTools.getJobState()
			.then(function(jobState) {
				if (_ws != null) {
					var action = DashboardAction.SetJobsState(jobState);
					sendMessage(action);
				}
			});
		_stream = _JOB_STREAM.then(function(jobStats) {
			if (_ws != null) {
				var action = DashboardAction.SetJobState(jobStats);
				sendMessage(action);
			}
		});
		_activeJobStream = _ACTIVE_JOB_STREAM.then(function(jobIds) {
			if (_ws != null) {
				var action = DashboardAction.SetActiveJobs(jobIds);
				sendMessage(action);
			}
		});

		// _finishedJobStream = _FINISHED_JOB_STREAM.then(function(jobIds) {
		// 	if (_ws != null) {
		// 		var action = DashboardAction.SetFinishedJobs(jobIds);
		// 		sendMessage(action);
		// 	}
		// });
	}
}