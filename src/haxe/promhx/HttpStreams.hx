package promhx;

import js.Error;
import js.node.http.*;
import js.node.Url;
import js.node.Http;
import js.node.Https;
import js.node.stream.Readable;
import js.node.stream.Writable;
import js.node.buffer.Buffer;

import promhx.Stream;

import t9.util.ColorTraces.*;

using StringTools;

class HttpStreams
{
	/**
	 * Returns a Stream that if a false value is returned, means that
	 * the connection failed (allowing for the configured retries).
	 * After a single failure (return of false), the Stream object is disposed.
	 * To dispose prior, call stream.end().
	 * @param  connection                   :Void->Bool   [description]
	 * @param  maxRetries                   :Int          [description]
	 * @param  doublingIntervalMilliseconds :Int          [description]
	 * @return                              [description]
	 */
	public static function createHttpGetStream(url :String) :Stream<String>
	{
		var stream = new promhx.deferred.DeferredStream();
		var ended = false;

		var cb = function(res :IncomingMessage) {
			res.on(ReadableEvent.Error, function(err) {
				if (stream != null) {
					stream.throwError({error:err, url:url});
					stream.boundStream.end();
					stream = null;
				} else {
					Log.error({error:err, stack:(err.stack != null ? err.stack : null)});
				}
			});

			res.on(ReadableEvent.Data, function(chunk :Buffer) {
				var string = chunk.toString();
				if (!ended) {
					stream.resolve(string);
				}
			});
			res.on(ReadableEvent.End, function() {
				if (stream != null) {
					stream.boundStream.end();
					stream = null;
				}
			});
		}
		var caller :{get:String->(IncomingMessage->Void)->ClientRequest} = url.startsWith('https') ? cast js.node.Https : cast js.node.Http;
		var request = null;
		try {
			request = caller.get(url, cb);
			request.on(WritableEvent.Error, function(err) {
				if (stream != null) {
					stream.throwError({error:err, url:url});
					stream = null;
				} else {
					Log.error({error:err, stack:(err.stack != null ? err.stack : null)});
				}
			});
		} catch(err :Dynamic) {
			if (stream != null) {
				stream.throwError({error:err, url:url});
				stream = null;
			}
		}

		stream.boundStream.endThen(function(_) {
			ended = true;
			request.abort();
		});

		return stream.boundStream;
	}
}
