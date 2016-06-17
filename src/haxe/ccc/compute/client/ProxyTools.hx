package ccc.compute.client;

/**
 * CLI tools for client/server/proxies.
 */
class ProxyTools
{
	public static function getProxy(rpcUrl :UrlString)
	{
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.ServiceBatchCompute)
			.setConnection(new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(rpcUrl));
		return proxy;
	}
}