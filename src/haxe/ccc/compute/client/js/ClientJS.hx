package ccc.compute.client.js;

import ccc.Definitions;
import t9.abstracts.net.*;

/**
 * Client package for node.js servers to use when interacting with
 * external CCC servers.
 */
@:keep
class ClientJS
{
	@:expose('connect')
	public static function connect (host :String)
	{
		if (host == null) {
			Log.warn('host argument is null, defaulting to "localhost:9000", the default local development server');
			host = 'localhost:9000';
		}
		var rpcUrl = ClientJSTools.rpcUrl(host);
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient("ccc.compute.server.execution.routes.RpcRoutes", false)
			.setUrl(rpcUrl);
		Reflect.setField(proxy, 'run', function(job, ?forms :Dynamic) {
			return ClientJSTools.postJob(host, job, forms);
		});
		return proxy;
	}
}