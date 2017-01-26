package ccc.compute.client.js;

import ccc.compute.shared.Definitions;
import ccc.compute.shared.*;
/**
 * Client package for node.js servers to use when interacting with
 * external CCC servers.
 */

import t9.abstracts.net.*;

@:keep
class ClientJS
{
	@:expose('connect')
	public static function connect (host :String)
	{
		var rpcUrl = 'sdsddsf';//ClientJSTools.rpcUrl(host);
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient("ccc.compute.server.ServiceBatchCompute", false)
			.setUrl(rpcUrl);
		// Reflect.setField(proxy, 'run', function(job, ?forms :Dynamic) {
		// 	return ClientJSTools.postJob(host, job, forms);
		// });
		return proxy;
	}
}