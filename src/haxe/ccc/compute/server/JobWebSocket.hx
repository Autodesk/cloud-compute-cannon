package ccc.compute.server;

import haxe.remoting.JsonRpc;

import promhx.deferred.DeferredPromise;

import t9.websockets.WebSocketConnection;

using promhx.PromiseTools;

/**
 * Methods used by both the client, server, and util classes.
 */
class JobWebSocket
{
	public static function getJobResult(host :Host, jobId :JobId, getJobResultData: Void->Promise<JobResult>) :Promise<JobResult>
	{
		if (jobId == null) {
			Log.warn('Null jobId passed');
			return Promise.promise(null);
		}
		function listenWebsocket() {
			var promise = new DeferredPromise();
			if (jobId != null) {
				var ws = new WebSocketConnection('ws://' + host);
				ws.registerOnMessage(function(data :Dynamic, ?flags) {
					try {
						var result :ResponseDef = Json.parse(data + '');
						if (result.error == null) {
							// var jobData :JobDataBlob = result.result;
							// JobTools.prependJobResultsUrls(jobData, hostport + '/');
							// promise.resolve(jobData);
							getJobResultData()
								.then(function(result) {
									if (!promise.boundPromise.isErroredOrFinished()) {
										promise.resolve(result);
									} else {
										Log.error('Promise already resolved/rejected, attempting resolving. getJobResult jobId=$jobId result=$result');
									}
								});
						} else {
							if (!promise.boundPromise.isErroredOrFinished()) {
								promise.boundPromise.reject(result.error);
							} else {
								Log.error('Promise already resolved/rejected, attempted rejection. getJobResult jobId=$jobId result=$result');
							}
						}
						ws.close();
					} catch(err :Dynamic) {
						Log.error(err);
						ws.close();
					}
				});
				ws.registerOnOpen(function () {
					ws.send(Json.stringify({method:Constants.RPC_METHOD_JOB_NOTIFY, params:{jobId:jobId}}));//, {binary: false}
					getJobResultData()
						.then(function(result) {
							if (result != null && !promise.boundPromise.isErroredOrFinished()) {
								promise.resolve(result);
							}
						})
						.catchError(function(err) {
							//Do nothing, file isn't there, wait for the websocket notification
						});
				});
				ws.registerOnClose(function(_) {
					if (!promise.boundPromise.isErroredOrFinished()) {
						promise.boundPromise.reject('Websocket closed prematurely');
					}
				});
			} else {
				promise.boundPromise.reject('jobId is null');
			}
			return promise.boundPromise;
		}
		return getJobResultData()
			.pipe(function(result) {
				if (result == null) {
					return listenWebsocket();
				} else {
					return Promise.promise(result);
				}
			})
			.errorPipe(function(err) {
				Log.error('Got error from getJobData() err=$err');
				return listenWebsocket();
			});
	}
}