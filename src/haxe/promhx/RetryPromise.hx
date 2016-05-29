package promhx;

import promhx.Deferred;
import promhx.Promise;

enum PollType {
	regular;
	decaying;
}

class RetryPromise
{
	public static function poll<T>(f :Void->Promise<T>, type :PollType, maxRetryAttempts :Int = 5, ?intervalMilliseconds :Int = 0, ?logPrefix :String = '', ?supressLogs :Bool= false) :Promise<T>
	{
		return switch(type) {
			case regular: pollRegular(f, maxRetryAttempts, intervalMilliseconds, logPrefix, supressLogs);
			case decaying: pollDecayingInterval(f, maxRetryAttempts, intervalMilliseconds, logPrefix, supressLogs);
		}
	}

	public static function pollRegular<T>(f :Void->Promise<T>, maxRetryAttempts :Int = 5, ?intervalMilliseconds :Int = 0, ?logPrefix :String = '', ?supressLogs :Bool= false) :Promise<T>
	{
		var deferred = new promhx.deferred.DeferredPromise();
		var attempts = 0;
		var retry = null;
		retry = function() {
			attempts++;
			var p = f();
			Assert.notNull(p, 'RetryPromise.pollRegular f() returned a null promise');
			p.then(function(val) {
				if (attempts > 1 && !supressLogs) {
					Log.info('$logPrefix Success after $attempts');
				}
				deferred.resolve(val);
			});
			p.catchError(function(err) {
				if (attempts < maxRetryAttempts) {
					if (!supressLogs) {
						Log.error('$logPrefix Failed attempt $attempts err=$err');
					}
					js.Node.setTimeout(retry, intervalMilliseconds);
				} else {
					if (!supressLogs) {
						Log.error('$logPrefix Failed all $maxRetryAttempts err=$err');
					}
					deferred.boundPromise.reject(err);
				}
			});
		}
		retry();
		return deferred.boundPromise;
	}

	public static function pollDecayingInterval<T>(f :Void->Promise<T>, maxRetryAttempts :Int = 5, ?doublingRetryIntervalMilliseconds :Int = 0, logPrefix :String, ?supressLogs :Bool= false) :Promise<T>
	{
		var deferred = new promhx.deferred.DeferredPromise();

		var attempts = 0;
		var currentDelay = doublingRetryIntervalMilliseconds;
		var retry = null;
		retry = function() {
			attempts++;
			var p = f();
			p.then(function(val) {
				if (attempts > 1 && !supressLogs) {
					Log.info('$logPrefix Success after $attempts');
				}
				deferred.resolve(val);
			});
			p.catchError(function(err) {
				if (attempts < maxRetryAttempts) {
					if (!supressLogs) {
						Log.error('$logPrefix Failed attempt $attempts err=$err');
					}
					js.Node.setTimeout(retry, currentDelay);
					currentDelay *= 2;
				} else {
					if (!supressLogs) {
						Log.error('$logPrefix Failed all $maxRetryAttempts err=$err');
					}
					deferred.boundPromise.reject(err);
				}
			});
		}
		retry();
		return deferred.boundPromise;
	}
}