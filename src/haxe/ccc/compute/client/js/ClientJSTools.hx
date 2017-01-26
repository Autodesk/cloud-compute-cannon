package ccc.compute.client.js;

import haxe.Json;

import ccc.compute.shared.Definitions;
import ccc.compute.shared.Constants;

import haxe.DynamicAccess;
import haxe.remoting.JsonRpc;

import js.node.Buffer;
import js.node.Http;
import js.node.http.IncomingMessage;

import promhx.Promise;
import promhx.RequestPromises;
import promhx.RetryPromise;
import promhx.deferred.DeferredPromise;

import t9.abstracts.net.*;

using StringTools;
using Lambda;

/**
 * Methods used by both the client, server, and util classes.
 */
class ClientJSTools
{
	@:expose
	public static function postJob(host :String, job :BasicBatchProcessRequest, ?forms :Dynamic) :Promise<JobResult>
	{
		var promise = new DeferredPromise();
		var jsonRpcRequest :RequestDef = {
			id: JsonRpcConstants.JSONRPC_NULL_ID,
			jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2,
			method: Constants.RPC_METHOD_JOB_SUBMIT,
			params: job
		}

		var formData = {
			jsonrpc: Json.stringify(jsonRpcRequest)
		};
		if (forms != null) {
			for (f in Reflect.fields(forms)) {
				Reflect.setField(formData, f, Reflect.field(forms, f));
			}
		}
		//Simply by making this request a multi-part request is is assumed
		//to be a job submission.
		js.npm.request.Request.post({url:rpcUrl(host), formData:formData},
			function(err :js.Error, httpResponse :js.npm.request.Request.HttpResponse, body:js.npm.request.Request.Body) {
				if (err != null) {
					Log.error(err);
					promise.boundPromise.reject(err);
					return;
				}
				if (httpResponse.statusCode == 200) {
					try {
						// var result :JobResult = Json.parse(body);
						var result :ResponseDefSuccess<JobResult> = Json.parse(body);
						promise.resolve(result.result);
					} catch (err :Dynamic) {
						promise.boundPromise.reject(err);
					}
				} else {
					promise.boundPromise.reject('non-200 response body=$body');
				}
			});
		return promise.boundPromise;
	}

	inline public static function rpcUrl(host :String) :UrlString
	{
		if (!host.startsWith('http')) {
			host = 'http://$host';
		}
		if (!host.endsWith(Constants.SERVER_RPC_URL)) {
			host = '$host${Constants.SERVER_RPC_URL}';
		}
		return new UrlString(host);
	}
}