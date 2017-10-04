package ccc.dashboard.action;

enum WebsocketAction
{
	Connect;
	Connected;
	Disconnect;
	Reconnect;
	ServerError(error :Dynamic, e :EnumValue);
}