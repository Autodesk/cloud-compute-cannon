package ccc.compute.client.js;

import ccc.compute.server.Definitions;
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
		var rpcUrl = ClientTools.rpcUrl(host);
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient("ccc.compute.server.ServiceBatchCompute", false)
			.setUrl(rpcUrl);
		Reflect.setField(proxy, 'run', function(job, ?forms :Dynamic) {
			return ClientTools.postJob(host, job, forms);
		});
		return proxy;
	}

#if test
	static function main()
	{
		var client = connect('http://localhost:9000');
		client.status().then(function(result) {
			trace(result);
		}).error(function(err) {
			trace(err);
		});

		var job :BasicBatchProcessRequest = {
			image: "docker.io/busybox:latest",
			cmd: ["ls", "/inputs"]
		};
		client.run(job, {testthing:"ssdfsdfdsf"})
			.then(function(result) {

			});
		// client.status()
		// 	.then(function(status) {
		// 		trace(status);
		// 	})
		// 	.catchError(function(error) {
		// 		trace('Error=${Json.stringify(error)}');
		// 	});
	}
#end
}