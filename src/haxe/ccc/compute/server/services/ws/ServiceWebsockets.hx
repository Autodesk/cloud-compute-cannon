package ccc.compute.server.services.ws;

import haxe.remoting.JsonRpc;
import haxe.Serializer;
import haxe.Unserializer;

import js.node.Url;
import js.npm.ws.WebSocket;
import js.npm.ws.WebSocketServer;
import js.npm.redis.RedisClient;

using util.ArrayTools;
using util.PromiseTools;
using Lambda;

class ServiceWebsockets
{
	function initializeWebsocketServer()
	{
		_wss = new WebSocketServer({server:_server});

		_injector.map(WebSocketServer).toValue(_wss);

		//Listen to websocket connections.
		_wss.on(WebSocketServerEvent.Connection, function(ws :WebSocket, req) {

			var url :String = req.url;
			Log.debug('Websocket connection request url=$url');
			switch(url) {
				case '/dashboard':
					var dashboardConnection = new WebsocketConnectionDashboard(ws);
					_injector.injectInto(dashboardConnection);
				case null,'','/':
					_jobMonitorConnections.handleWebsocketConnection(ws);
				default:
					Log.warn({message : 'Unhandled websocket connection for path, disconnecting', url: url});
					ws.close(1011, 'No handler for this path=$url');
			}
		});
	}

	@post
	public function postInject()
	{
		_jobMonitorConnections = new WebsocketConnectionsJobMonitor();
		_injector.injectInto(_jobMonitorConnections);
		initializeWebsocketServer();
	}

	public function new() {}

	var _wss :WebSocketServer;
	var _jobMonitorConnections :WebsocketConnectionsJobMonitor;

	@inject public var _server :js.node.http.Server;
	@inject public var _injector :minject.Injector;
	@inject public var _redis: ServerRedisClient;
}