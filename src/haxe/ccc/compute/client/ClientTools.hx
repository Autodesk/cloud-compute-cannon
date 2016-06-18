package ccc.compute.client;

import promhx.RequestPromises;
import promhx.RetryPromise;

/**
 * Methods used by both the client, server, and util classes.
 */
class ClientTools
{
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
		trace('url=${url}');
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