package promhx;

import promhx.deferred.DeferredPromise;
import promhx.Promise;

import js.Error;
import js.node.http.*;
import js.node.Url;
import js.node.Http;
import js.node.Https;
import js.node.stream.Readable;
import js.node.stream.Writable;
import js.node.buffer.Buffer;

using promhx.PromiseTools;
using StringTools;

class RequestPromises
{
	public static function get(url :String, ?timeout :Int = 0) :Promise<String>
	{
		return getBuffer(url, timeout)
			.then(function(buffer) {
				return buffer != null ? buffer.toString('utf8') : null;
			});
	}

	public static function getBuffer(url :String, ?timeout :Int = 0) :Promise<Buffer>
	{
		var promise = new DeferredPromise();
		var responseString = '';
		var responseBuffer :Buffer = null;
		var cb = function(res :IncomingMessage) {
			res.on(ReadableEvent.Error, function(err) {
				if (promise != null) {
					promise.boundPromise.reject({error:err, url:url});
					promise = null;
				} else {
					Log.error({error:err, stack:(err.stack != null ? err.stack : null)});
				}
			});
			res.connection.on('error', function(err) {
				Log.error('response socket error for $url err=$err');
			});

			res.on(ReadableEvent.Data, function(chunk :Buffer) {
				if (responseBuffer == null) {
					responseBuffer = chunk;
				} else {
					responseBuffer = Buffer.concat([responseBuffer, chunk]);
				}
			});
			res.on(ReadableEvent.End, function() {
				if (promise != null) {
					if (res.statusCode < 200 || res.statusCode > 299) {
						promise.boundPromise.reject(responseBuffer);
					} else {
						promise.resolve(responseBuffer);
					}
					promise = null;
				}
			});
		}
		var caller :{get:String->(IncomingMessage->Void)->ClientRequest} = url.startsWith('https') ? cast js.node.Https : cast js.node.Http;
		var request = null;
		try {
			request = caller.get(url, cb);
			request.on(WritableEvent.Error, function(err) {
				if (promise != null) {
					promise.boundPromise.reject({error:err, url:url});
					promise = null;
				} else {
					Log.error(err);
				}
				request.abort();
			});

			if (timeout > 0) {
				request.setTimeout(timeout, function() {
					var err = {url:url, error:'timeout', timeout:timeout};
					if (promise != null) {
						promise.boundPromise.reject(err);
						promise = null;
					} else {
						Log.error(err);
					}
					request.abort();
				});
			}
		} catch(err :Dynamic) {
			if (promise != null) {
				promise.boundPromise.reject({error:err, url:url});
			}
		}
		return promise.boundPromise;
	}

	public static function post(url :String, data :String) :Promise<String>
	{
		var promise = new DeferredPromise();
		var responseBuffer :Buffer = null;
		var cb = function(res :IncomingMessage) :Void {
			res.on(ReadableEvent.Error, function(err) {
				if (promise != null) {
					promise.boundPromise.reject({error:err, url:url});
					promise = null;
				}
			});
			if (res.statusCode < 200 || res.statusCode > 299) {
				if (promise != null) {
					promise.boundPromise.reject('ERROR status code ${res.statusCode}');
					promise = null;
				}
			} else {
				res.on(ReadableEvent.Data, function(chunk) {
					if (responseBuffer == null) {
						responseBuffer = chunk;
					} else {
						responseBuffer = Buffer.concat([responseBuffer, chunk]);
					}
				});
				res.on(ReadableEvent.End, function() {
					if (promise != null) {
						promise.resolve(responseBuffer != null ? responseBuffer.toString('utf8') : null);
						promise = null;
					}
				});
			}
		}
		var bufferData = new Buffer(data, 'utf8');
		var options :HttpRequestOptions = cast Url.parse(url);
		Reflect.setField(options, 'method', 'POST');
		Reflect.setField(options, 'headers', {
			'Content-Type': 'application/x-www-form-urlencoded',
			'Content-Length': bufferData.byteLength
		});
		var caller :{request:HttpRequestOptions->(IncomingMessage->Void)->ClientRequest} = url.startsWith('https') ? cast js.node.Https : cast js.node.Http;
		var request = null;
		try {
			request = caller.request(options, cb);
			request.on(WritableEvent.Error, function(err) {
				if (promise != null) {
					promise.resolve(responseBuffer != null ? responseBuffer.toString('utf8') : null);
					promise = null;
				} else {
					Log.error(err);
				}
			});
		} catch(err :Dynamic) {
			promise.boundPromise.reject(err);
			var p = promise.boundPromise;
			promise = null;
			return p;
		}
		// post the data
		request.write(bufferData);
		request.end();
		return promise.boundPromise;
	}

	public static function postStreams(url :String, data :IReadable) :Promise<IncomingMessage>
	{
		var promise = new DeferredPromise();
		var responseString = '';
		var cb = function(res :IncomingMessage) :Void {
			if (res.statusCode < 200 || res.statusCode > 299) {
				promise.boundPromise.reject('ERROR status code ${res.statusCode} for url=$url');
			} else {
				promise.resolve(res);
			}
		}
		var options :HttpRequestOptions = cast Url.parse(url);
		Reflect.setField(options, 'method', 'POST');
		var caller :{request:HttpRequestOptions->(IncomingMessage->Void)->ClientRequest} = url.startsWith('https') ? cast js.node.Https : cast js.node.Http;
		var request = null;
		try {
			request = caller.request(options, cb);
			request.on(WritableEvent.Error, function(err) {
				if (!promise.boundPromise.isResolved()) {
					promise.boundPromise.reject(err);
				} else {
					Log.error(err);
				}
			});
		} catch(err :Dynamic) {
			promise.boundPromise.reject(err);
		}
		// post the data
		data.pipe(request);
		return promise.boundPromise;
	}
}