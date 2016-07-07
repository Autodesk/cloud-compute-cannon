package ccc.compute.client;

import haxe.remoting.JsonRpc;

import promhx.RequestPromises;
import promhx.RetryPromise;
import promhx.deferred.DeferredPromise;

/**
 * Methods used by both the client, server, and util classes.
 */
class ClientTools
{
	public static function getJobResult(host :Host, jobId :JobId, getJobResultData: Void->Promise<JobResult>) :Promise<JobResult>
	{
		return JobWebSocket.getJobResult(host, jobId, getJobResultData);
	}

	public static function waitUntilServerReady(host :Host, ?maxAttempts :Int = 300, ?delayMilliseconds :Int = 1000) :Promise<Bool>
	{
		return pollServerListening(host, maxAttempts, delayMilliseconds)
			.pipe(function(_) {
				return isServerReady(host);
			});
	}

	public static function isServerListening(host :Host, ?swallowErrors :Bool = true) :Promise<Bool>
	{
		var url = 'http://${host}${SERVER_PATH_CHECKS}';
		return RequestPromises.get(url)
			.then(function(out) {
				return out.trim() == SERVER_PATH_CHECKS_OK;
			})
			.errorPipe(function(err) {
				if (!swallowErrors) {
					Log.error({error:err, url:url});
				}
				return Promise.promise(false);
			});
	}

	public static function pollServerListening(host :Host, maxAttempts :Int, delay :Int, ?swallowErrors :Bool = true) :Promise<Bool>
	{
		return RetryPromise.pollRegular(
			function() {
				return isServerListening(host, swallowErrors)
					.then(function(ready) {
						if (!ready) {
							throw 'No connected';
						}
						return ready;
					});
			}, maxAttempts, delay);
	}

	public static function isServerReady(host :Host, ?swallowErrors :Bool = true) :Promise<Bool>
	{
		var url = 'http://${host}${SERVER_PATH_READY}';
		return RequestPromises.get(url)
			.then(function(out) {
				return true;
			})
			.errorPipe(function(err) {
				if (!swallowErrors) {
					Log.error({error:err, url:url});
				}
				return Promise.promise(false);
			});
	}

}