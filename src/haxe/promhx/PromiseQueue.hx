package promhx;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

typedef QueueElement<T> = {
	var f :Void->Promise<T>;
	var p :DeferredPromise<T>;
}

class PromiseQueue
{
	public function new () {}

	public function enqueue<T>(f :Void->Promise<T>, ?timeout :Int = -1) :Promise<T>
	{
		var deferred = new DeferredPromise<T>();
		var e :QueueElement<T> = {f:f, p:deferred};
		_queue.unshift(cast e);
		process();

		if (timeout > 0) {
			haxe.Timer.delay(function() {
				if (!deferred.boundPromise.isResolved()) {
					deferred.boundPromise.reject('Timeout');
				}
			}, timeout);
		}
		return deferred.boundPromise;
	}

	public function whenEmpty() :Promise<Bool>
	{
		if (_queue.length == 0 && !_processing) {
			return Promise.promise(true);
		} else {
			var deferred = new DeferredPromise<Bool>();
			_emptyPromises.unshift(deferred);
			return deferred.boundPromise;
		}
	}

	public function isEmpty() :Bool
	{
		return _queue.length == 0 && !_processing;
	}

	public function dispose()
	{
		_emptyPromises = [];
		_queue = [];
		_processing = false;
	}

	function process()
	{
		if (_processing) {
			return;
		}
		// trace('PromiseQueue _processing _queue.length=${_queue.length}');
		var e = _queue.pop();
		if (e == null) {
			var emptyPromise = _emptyPromises.pop();
			if (emptyPromise != null) {
				emptyPromise.resolve(true);
				process();
			}
			return;
		}
		if (e.p.isResolved()) {
			process();
		} else {
			_processing = true;
			var promise = e.f();
			if (promise == null) {
				promise = Promise.promise(null);
			}

			promise.then(function(val) {
				e.p.resolve(val);
				_processing = false;
				//Process on the next tick, just in case a new item
				//is added on the queue following a resolve.
				Promise.promise(true)
					.then(function(_) {
						process();
					});
				return val;
			});

			promise.catchError(function(err) {
				Log.error(err);
				e.p.boundPromise.reject(err);
				_processing = false;
				process();
				throw err;
			});
		}
	}

	var _queue :Array<QueueElement<Dynamic>> = [];
	var _processing = false;
	var _emptyPromises = new Array<DeferredPromise<Bool>>();
}