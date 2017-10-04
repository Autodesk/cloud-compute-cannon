package ccc.dashboard.model;

import haxe.Serializer;
import haxe.Unserializer;

import js.html.WebSocket;
import js.html.MessageEvent;
import js.Browser;

import js.react.util.WebsocketTools;

import redux.Redux;

/**
	Redux actions to dispatch from views and match in reducer/middleware
**/
enum WebsocketConnectionStatus
{
	Connecting;
	Connected;
	Disconnected;
}

typedef WebsocketState = {
	var status :WebsocketConnectionStatus;
}

class WebsocketMiddleware
	implements IReducer<WebsocketAction, WebsocketState>
{
	public var initState :WebsocketState = {
		status: WebsocketConnectionStatus.Connecting,
	};
	public var store :StoreMethods<ApplicationState>;

	var _ws :WebSocket;
	var _queuedMessages :Array<Action> = [];

	public function new()
	{
	}

	function onWebsocketMessage(event :MessageEvent)
	{
		var message = event.data;
		switch(WebsocketTools.decodeMessage(message)) {
			case JsonMessage(obj):
				trace('Unhandled websocket JSON message=${Json.stringify(obj)}');
			case Unknown(unknown):
				trace('Error unknown websocket message=$message');
			case DecodingWebsocketError(error, message):
				trace('Error decoding websocket message=$message error=$error');
			case ActionMessage(action):
				// trace('on websocket message $action');
				store.dispatch(action);
		}
	}

	/* SERVICE */

	public function reduce(state :WebsocketState, action :WebsocketAction) :WebsocketState
	{
		return switch(action)
		{
			case Connect:
				copy(state, {status: WebsocketConnectionStatus.Connecting});
			case Connected:
				copy(state, {status: WebsocketConnectionStatus.Connected});
			case Disconnect:
				copy(state, {status: WebsocketConnectionStatus.Disconnected});
			case Reconnect:
				copy(state, {status: WebsocketConnectionStatus.Connecting});
			case ServerError(error, action):
				state;
		}
	}

	/* MIDDLEWARE */

	public function createMiddleware()
	{
		return function (store:StoreMethods<ApplicationState>) {
			this.store = store;
			return function (next:Dispatch):Dynamic {
				return function (action:Action):Dynamic {
					if (action == null) {
						throw 'action == null';
					}
					if (action.type == null) {
						throw 'action.type == null, action=${action}';
					}
					switch(action.type) {
						case 'ccc.dashboard.action.DashboardAction':
							var en :DashboardAction = cast action.value;
						case 'ccc.dashboard.action.WebsocketAction':
							var en :WebsocketAction = cast action.value;
							switch(en) {
								case Connect,Reconnect:
									connect();
								case Disconnect:
									disconnect();
								case Connected:
								case ServerError(error, action):
									trace('Error returned from server error=${error} action=${action}');
							}
						default: throw 'Unknown enum type ${action.type}';
					}

					return next(action);
				}
			}
		}
	}

	function sendAction(action :Action)
	{
		if (_ws != null && _ws.readyState == WebSocket.OPEN) {
			_ws.send(WebsocketTools.encodeAction(action));
		} else {
			// if (action.type != Type.enumConstructor(UserAction.SetLoginToken(null).addToJson())) {
				_queuedMessages.push(action);
			// }
		}
	}

	function connect()
	{
		disconnect();
		trace('sheeet');
		var port = Browser.location.port != null ? ":" + Browser.location.port : "";
#if DEV
		//Force the debug websocket to avoid clobbering the livereloadx websocket
		port = ":9001";
#end
		var protocol = Browser.location.protocol == "https:" ? "wss:" : "ws:";
		var wsUrl = '${protocol}//${Browser.location.hostname}${port}/dashboard';
		_ws = new WebSocket(wsUrl);
		Reflect.setField(Browser.window, 'WS_INSTANCE', _ws);
		_ws.onerror = onWebsocketError;
		_ws.onopen = onWebsocketOpen;
		_ws.onclose = onWebsocketClose;
		_ws.onmessage = onWebsocketMessage;
	}

	function disconnect()
	{
		var closeAndCleanup = function() {
			if (_ws != null) {
				_ws.onopen = null;
				_ws.onerror = null;
				_ws.onclose = null;
				_ws.onmessage = null;
				_ws.close();
				_ws = null;
			}
		};
		closeAndCleanup();
		//Check static bound websocket, to reduce craziness when hot-loading
		_ws = Reflect.field(Browser.window, 'WS_INSTANCE');
		Reflect.deleteField(Browser.window, 'WS_INSTANCE');
		closeAndCleanup();
	}

	function onWebsocketError(err :Dynamic)
	{
		trace('websocket error ${Json.stringify(err)}');
	}

	function onWebsocketOpen()
	{
		// trace('websocket opened _queuedMessages.length=${_queuedMessages.length}');
		store.dispatch(WebsocketAction.Connected);
		//Send the token, if we have it
		// if (store.getState().user.token != null) {
		// 	// var blob :JWTContent = js.npm.jwtdecode.JWTDecode.decode(store.getState().user.token);
		// 	// trace('store.getState().user.token=${blob}');
		// 	var action = Action.map(UserAction.SetLoginToken(store.getState().user.token).addToJson());
		// 	// trace('sending ${Json.stringify(action)}');
		// 	_ws.send(WebsocketTools.encodeAction(action));
		// }
		while (_queuedMessages.length > 0) {
			// trace('SENDING QUEUED MESSAGE ${_queuedMessages[0]}');
			_ws.send(WebsocketTools.encodeAction(_queuedMessages.shift()));
		}
	}

	function onWebsocketClose(reason :js.html.CloseEvent)
	{
		if (store.getState().ws != null) {

		}
		switch (store.getState().ws.status) {
			case Connecting,Connected:
				trace('websocket closed but status=${store.getState().ws.status}, so reconnecting');
				//Websocket got disconnected prematurely, reconnect
				Browser.window.setTimeout(function() {
					store.dispatch(WebsocketAction.Reconnect);
				}, 5000);
			case Disconnected://Good
		}
	}
}
