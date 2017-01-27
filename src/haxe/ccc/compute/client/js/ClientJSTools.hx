package ccc.compute.client.js;

import haxe.Json;

import ccc.compute.shared.Definitions;
import ccc.compute.shared.Constants;

import haxe.DynamicAccess;
import haxe.remoting.JsonRpc;

import js.node.Buffer;
import js.node.Http;
import js.node.http.IncomingMessage;

import js.npm.request.Request;

import t9.abstracts.net.*;

using StringTools;
using Lambda;

#if (promise == "js.npm.bluebird.Bluebird")
	typedef Promise<T>=js.npm.bluebird.Bluebird<T,Dynamic>;
#else
	typedef Promise<T>=promhx.Promise<T>;
#end

/**
 * Methods used by both the client, server, and util classes.
 */
class ClientJSTools
{
	@:expose
	public static function postJob(host :String, job :BasicBatchProcessRequest, ?forms :Dynamic) :Promise<JobResult>
	{
		var execute = function(resolve :JobResult->Void, reject :Dynamic->Void) {

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
			var url = rpcUrl(host);
			Request.post({url:url, formData:formData},
				function(err :js.Error, httpResponse :HttpResponse, body:Body) {
					if (err != null) {
						Log.error(err);
						reject(err);
						return;
					}
					if (httpResponse.statusCode == 200) {
						try {
							var result :ResponseDefSuccess<JobResult> = Json.parse(body);
							resolve(result.result);
						} catch (err :Dynamic) {
							reject(err);
						}
					} else {
						reject('non-200 response body=$body');
					}
				});
		}

#if (promise == "js.npm.bluebird.Bluebird")
		return new Promise(execute);
#else
		var promise = new DeferredPromise();
		execute(promise.resolve, promise.boundPromise.reject);
		return promise.boundPromise;
#end
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