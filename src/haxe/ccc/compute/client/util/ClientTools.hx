package ccc.compute.client.util;

import haxe.Json;
import haxe.DynamicAccess;

import js.node.Buffer;
import js.node.http.IncomingMessage;

import ccc.compute.shared.*;
import ccc.compute.shared.Constants.*;
import ccc.compute.shared.Definitions;
import ccc.compute.shared.TypedDynamicObject;
import ccc.compute.server.*;

import haxe.remoting.JsonRpc;

import promhx.*;
import promhx.deferred.*;

import t9.abstracts.net.*;
import t9.util.ColorTraces.*;

using StringTools;

/**
 * Methods used by both the client, server, and util classes.
 */
class ClientTools
{
	public static function postApi<T>(host :Host, method :String, params :Dynamic) :Promise<T>
	{
		var jsonRpcRequest :RequestDef = {
				id: JsonRpcConstants.JSONRPC_NULL_ID,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2,
				method: method,
				params: params
			}

		var promise = new DeferredPromise();

		var jsonRpcString = Json.stringify(jsonRpcRequest);
		var post_options = {
			host: host.getHostname(),
			port: host.port(),
			path: SERVER_RPC_URL,
			method: 'POST',
			headers: {
				'Content-Type': 'application/json-rpc',
				'Content-Length': Buffer.byteLength(jsonRpcString)
			}
		};

		// Set up the request
		var req = js.node.Http.request(cast post_options, function(res :IncomingMessage) {
			var buffer :Buffer = null;
			res.on('data', function(chunk) {
				if (buffer == null) {
					buffer = chunk;
				} else {
					buffer = Buffer.concat([buffer, chunk]);
				}
			});
			res.on('error', function (err) {
				err.statusCode = res.statusCode;
				promise.boundPromise.reject(err);
			});
			res.on('end', function (chunk) {
				var body = buffer.toString('utf8');
				try {
					var result = Json.parse(body);
					if (res.statusCode != 200) {
						result.statusCode = res.statusCode;
						result.request = Json.parse(jsonRpcString);
						traceRed(result);
						promise.boundPromise.reject(result);
					} else {
						promise.resolve(result.result);
					}
				} catch (err :Dynamic) {
					traceRed(err);
					promise.boundPromise.reject({statusCode:res.statusCode, err:err, message:'Got error parsing job result JSON', body:body});
				}
			});
		});
		req.on('error', function (err) {
			traceRed(err);
			promise.boundPromise.reject({err:err});
		});

		// post the data
		req.write(jsonRpcString);
		req.end();

		return promise.boundPromise;
	}

	public static function getJobResultData(host :Host, jobId :JobId) :Promise<JobResult>
	{
		if (jobId == null) {
			Log.warn('Null jobId passed');
			return Promise.promise(null);
		} else {
			var jsonRpcRequest :RequestDef = {
				id: JsonRpcConstants.JSONRPC_NULL_ID,
				jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2,
				method: 'job',
				params: {
					command: JobCLICommand.Result,
					jobId:jobId
				}
			}

			return postApi(host, 'job', {command: JobCLICommand.Result,jobId:[jobId]})
				.then(function(out :DynamicAccess<JobResult>) {
					return out[jobId];
				});
		}
	}

	public static function getJobResult(host :Host, jobId :JobId) :Promise<JobResult>
	{
		return JobWebSocket.getJobResult(host, jobId, getJobResultData.bind(host, jobId));
	}

	public static function waitUntilServerReady(host :Host, ?maxAttempts :Int = 300, ?delayMilliseconds :Int = 1000) :Promise<Bool>
	{
		return pollServerListening(host, maxAttempts, delayMilliseconds)
			.pipe(function(_) {
				return isServerReady(host);
			});
	}

	public static function isServerListening(host :Host, ?swallowErrors :Bool = false) :Promise<Bool>
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