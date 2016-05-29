package js.npm;

import js.Node;
import js.node.Http;
import js.node.Url;
import js.node.stream.Readable;
import js.node.stream.Writable;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

class HttpPromises
{
	public static function get(url :String) :Promise<String>
	{
		var deferred = new DeferredPromise();
		var opts = Url.parse(url);
		var req = Http.request(cast opts, function(res) {
			res.setEncoding('utf8');
			var body = '';
			res.on(ReadableEvent.Data, function (chunk) {
				body += chunk;
			});
			res.on(ReadableEvent.End, function() {
				if (!deferred.isResolved()) {
					deferred.resolve(body);
				}
			});
			res.on(ReadableEvent.Error, function(error) {
				if (!deferred.isResolved()) {
					deferred.boundPromise.reject(error);
				} else {
					Log.error({error:error, url:url});
				}
			});
		});
		req.on(WritableEvent.Error, function(error) {
			if (!deferred.isResolved()) {
				deferred.boundPromise.reject(error);
			} else {
				Log.error({error:error, url:url});
			}
		});
		req.end();
		return deferred.boundPromise;
	}

	public static function post(url :String, postData :String) :Promise<String>
	{
		var deferred = new DeferredPromise();
		var opts :HttpRequestOptions = cast Url.parse(url);
		opts.method = 'POST';
		opts.headers = {
			'Content-Type': 'application/x-www-form-urlencoded',
			'Content-Length': postData.length
		};
		var req = Http.request(opts, function(res) {
			res.setEncoding('utf8');
			var body = '';
			res.on(ReadableEvent.Data, function (chunk) {
				body += chunk;
			});
			res.on(ReadableEvent.End, function() {
				deferred.resolve(body);
			});
			res.on(ReadableEvent.Error, function(error) {
				if (!deferred.isResolved()) {
					deferred.boundPromise.reject(error);
				} else {
					Log.error({error:error, url:url, post_data:postData});
				}
			});
		});

		req.on(WritableEvent.Error, function(error) {
			if (!deferred.isResolved()) {
				deferred.boundPromise.reject(error);
			} else {
				Log.error({error:error, url:url, post_data:postData});
			}
		});

		// write data to request body
		req.write(postData);
		req.end();
		return deferred.boundPromise;
	}
}