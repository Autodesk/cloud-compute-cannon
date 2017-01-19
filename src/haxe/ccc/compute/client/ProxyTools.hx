package ccc.compute.client;

/**
 * CLI tools for client/server/proxies.
 */
class ProxyTools
{
	public static function getProxy(rpcUrl :UrlString)
	{
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.server.ServiceBatchCompute)
			.setConnection(new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(rpcUrl));
		return proxy;
	}

	public static function getTestsProxy(rpcUrl :UrlString)
	{
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.server.tests.ServiceTests)
			.setConnection(new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(rpcUrl));
		return proxy;
	}
}