package promhx;

import promhx.Promise;
import promhx.base.AsyncBase;
import promhx.deferred.DeferredPromise;
import promhx.RetryPromise;

class PollStreams
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
	public static function pollValue<T>(
		connection :Void->Promise<Dynamic>,
		type :PollType,
		pollIntervalMs :Int,
		maxRetries :Int,
		doublingRetryIntervalMs :Int,
		?logPrefix :String = '',
		?supressLogs :Bool= false) :Stream<Bool>
	{
		var stream = new promhx.deferred.DeferredStream();
		var ended = false;

		stream.boundStream.endThen(function(_) {
			ended = true;
		});

		var poll = null;
		poll = function() {
			if (ended) {
				return;
			}
			RetryPromise.poll(connection, type, maxRetries, doublingRetryIntervalMs, logPrefix, supressLogs)
				.then(function(val) {
					if (!ended) {
						stream.resolve(val);
						haxe.Timer.delay(poll, pollIntervalMs);
					}
				})
				.catchError(function(err) {
					traceRed(err);
					if (!ended) {
						stream.throwError(err);
					}
				});
		}
		poll();

		return stream.boundStream;
	}

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
	// public static function poll<T>(
	// 	connection :Void->Promise<Dynamic>,
	// 	type :PollType,
	// 	pollIntervalMs :Int,
	// 	maxRetries :Int,
	// 	doublingRetryIntervalMs :Int,
	// 	?logPrefix :String = '',
	// 	?supressLogs :Bool= false) :Stream<Bool>
	// {
	// 	var stream = new promhx.deferred.DeferredStream();
	// 	var ended = false;

	// 	stream.boundStream.endThen(function(_) {
	// 		ended = true;
	// 	});

	// 	var poll = null;
	// 	poll = function() {
	// 		if (ended) {
	// 			return;
	// 		}
	// 		promhx.RetryPromise.poll(connection, type, maxRetries, doublingRetryIntervalMs, logPrefix, supressLogs)
	// 			.then(function(_) {
	// 				if (!ended) {
	// 					stream.resolve(true);
	// 					haxe.Timer.delay(poll, pollIntervalMs);
	// 				}
	// 			})
	// 			.catchError(function(err) {
	// 				if (!ended) {
	// 					stream.resolve(false);
	// 					stream.boundStream.end();
	// 				}
	// 			});
	// 	}
	// 	poll();

	// 	return stream.boundStream;
	// }

	/**
	 * Returns true if the poll returned any value, and false if an
	 * error was thrown.
	 * FALSEEEEEEE If false is returned the stream and polling
	 * is ended.
	 * @param  connection              :Void->Promise<Dynamic> [description]
	 * @param  type                    :PollType               [description]
	 * @param  pollIntervalMs          :Int                    [description]
	 * @param  maxRetries              :Int                    [description]
	 * @param  doublingRetryIntervalMs :Int                    [description]
	 * @param  ?logPrefix              :String                 [description]
	 * @param  ?supressLogs            :Bool                   [description]
	 * @return                         [description]
	 */
	public static function pollForError(
		connection :Void->Promise<Dynamic>,
		type :PollType, pollIntervalMs :Int,
		maxRetries :Int,
		doublingRetryIntervalMs :Int,
		?logPrefix :String = '',
		?supressLogs :Bool= false) :Stream<Bool>
	{
		var p :Stream<Dynamic> = pollValue(connection, type, pollIntervalMs, maxRetries, doublingRetryIntervalMs, logPrefix, supressLogs);

		var finalP = p
			.then(function(ignored) {
				return true;
			})
			.errorPipe(function(err) {
				return Stream.stream(false);
			});
		finalP.endThen(function(_) {
			p.end();
		});
		return finalP;
	}
}
