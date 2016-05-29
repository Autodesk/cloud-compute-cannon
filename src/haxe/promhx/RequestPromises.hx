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
	public static function get(url :String) :Promise<String>
	{
		var promise = new DeferredPromise();
		var responseString = '';
		var cb = function(res :IncomingMessage) {
			if (res.statusCode < 200 || res.statusCode > 299) {
				promise.boundPromise.reject('ERROR status code ${res.statusCode}');
			} else {
				res.on(ReadableEvent.Data, function(d) {
					responseString += d;
				});
				res.on(ReadableEvent.End, function() {
					promise.resolve(responseString);
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
		} catch(err :Dynamic) {
			promise.boundPromise.reject(err);
		}
		return promise.boundPromise;
	}

	// public static function getStream(url :String) :Promise<IReadable>
	// {
	// 	var promise = new DeferredPromise();
	// 	var transform :js.node.stream.Transform = untyped __js__('new require("stream").Transform({decodeStrings:false,objectMode:false})');
	// 	untyped transform._transform = function(chunk :String, encoding :String, callback) {
	// 		callback(null, chunk);
	// 	};
	// 	var cb = function(res) {
	// 		if (res.statusCode < 200 || res.statusCode > 299) {
	// 			promise.boundPromise.reject('ERROR status code ${res.statusCode}');
	// 		} else {
	// 			res.on(ReadableEvent.Error, function(err) {
	// 				transform.dispatchEvent(err);
	// 			});

	// 			transform.on(ReadableEvent.End, function() {
	// 				res.
	// 			})
				
	// 			res.on('data', function(d) {
	// 				responseString += d;
	// 			});
	// 			res.on('end', function(d) {
	// 				promise.resolve(responseString);
	// 			});

	// 			promise.resolve(transform);
	// 		}
	// 	}
	// 	var request =
	// 		if (url.startsWith('https')) {
	// 			js.node.Https.get(cast url, cb);
	// 		} else {
	// 			js.node.Http.get(cast url, cb);
	// 		}

	// 	request.on('error', function(err) {
	// 		if (!promise.boundPromise.isResolved()) {
	// 			promise.boundPromise.reject(err);
	// 		} else {
	// 			Log.error(err);
	// 		}
	// 	});
	// 	return promise.boundPromise;
	// }

	public static function post(url :String, data :String) :Promise<String>
	{
		var promise = new DeferredPromise();
		var responseString = '';
		var cb = function(res :IncomingMessage) :Void {
			if (res.statusCode < 200 || res.statusCode > 299) {
				promise.boundPromise.reject('ERROR status code ${res.statusCode}');
			} else {
				res.on(ReadableEvent.Data, function(d) {
					responseString += d;
				});
				res.on(ReadableEvent.End, function() {
					promise.resolve(responseString);
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