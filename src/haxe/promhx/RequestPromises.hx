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

using StringTools;

class RequestPromises
{
	public static function get(url :String, ?timeout :Int = 0) :Promise<String>
	{
		var promise = new DeferredPromise();
		var responseString = '';
		var responseBuffer :Buffer = null;
		var cb = function(res :IncomingMessage) {
			res.setEncoding('utf8');
			if (res.statusCode < 200 || res.statusCode > 299) {
				promise.boundPromise.reject('ERROR status code ${res.statusCode}');
			} else {
				res.on(ReadableEvent.Data, function(chunk :Buffer) {
					if (responseBuffer == null) {
						responseBuffer = chunk;
					} else {
						responseBuffer = Buffer.concat([responseBuffer, chunk]);
					}
				});
				res.on(ReadableEvent.End, function() {
					promise.resolve(responseBuffer != null ? responseBuffer.toString('utf8') : null);
				});
			}
		}
		var caller :{get:String->(IncomingMessage->Void)->ClientRequest} = url.startsWith('https') ? cast js.node.Https : cast js.node.Http;
		var request = null;
		try {
			request = caller.get(url, cb);
			request.on(WritableEvent.Error, function(err) {
				if (!promise.boundPromise.isResolved()) {
					promise.boundPromise.reject(err);
				} else {
					Log.error(err);
				}
			});
			if (timeout > 0) {
				request.setTimeout(timeout, function() {
					var err = {url:url, error:'timeout', timeout:timeout};
					if (!promise.boundPromise.isResolved()) {
						promise.boundPromise.reject(err);
					} else {
						Log.error(err);
					}
				});
			}
		} catch(err :Dynamic) {
			promise.boundPromise.reject(err);
		}
		return promise.boundPromise;
	}

	public static function post(url :String, data :String) :Promise<String>
	{
		var promise = new DeferredPromise();
		var responseBuffer :Buffer = null;
		var cb = function(res :IncomingMessage) :Void {
			if (res.statusCode < 200 || res.statusCode > 299) {
				promise.boundPromise.reject('ERROR status code ${res.statusCode}');
			} else {
				res.on(ReadableEvent.Data, function(chunk) {
					if (responseBuffer == null) {
						responseBuffer = chunk;
					} else {
						responseBuffer = Buffer.concat([responseBuffer, chunk]);
					}
				});
				res.on(ReadableEvent.End, function() {
					promise.resolve(responseBuffer != null ? responseBuffer.toString('utf8') : null);
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