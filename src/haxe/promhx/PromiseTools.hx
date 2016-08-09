package promhx;

import haxe.Timer;

import promhx.Promise;
import promhx.base.AsyncBase;
import promhx.deferred.DeferredPromise;

class PromiseTools
{
	public static function untilTrue(f :Void->Promise<Bool>, ?interval :Int = 1000, ?max :Int = 100) :Promise<Bool>
	{
		var promise = new DeferredPromise();
		var check = null;
		var count = 0;
		check = function() {
			count++;
			f().then(function(result) {
				if (result) {
					if (promise != null) {
						promise.resolve(true);
						promise = null;
					}
				} else {
					if (count < max) {
						Timer.delay(check, interval);
					} else {
						if (promise != null) {
							promise.boundPromise.reject('count >= max($max)');
							promise = null;
						}
					}
				}
			})
			.catchError(function(err) {
				if (promise != null) {
					promise.boundPromise.reject(err);
					promise = null;
				}
			});
		}
		check();
		return promise.boundPromise;
	}

	public static function orTrue(p :Promise<Bool>) :Promise<Bool>
	{
		return p != null ? p : Promise.promise(true);
	}

	public static function isErroredOrFinished(p :Promise<Dynamic>) :Bool
	{
		return p.isErrored() || p.isFulfilled() || p.isRejected();
	}

	public static function isDeferredErroredOrFinished(p :DeferredPromise<Dynamic>) :Bool
	{
		return p.isErrored() || p.isFulfilled() || p.boundPromise.isErrored() || p.boundPromise.isFulfilled() || p.boundPromise.isRejected();
	}

	public static function error<A>(err :Dynamic) :Promise<A>
	{
		var p = new Promise();
		js.Node.setTimeout(function() {
			p.reject(err);
		}, 1);
		return p;
	}

	public static function thenF<A,B>(promise :Promise<A>, f :A->B) :Promise<B>
	{
		return promise.then(function(a :A) {
			return f(a);
		});
	}

	public static function thenTrue(promise :Promise<Dynamic>) :Promise<Bool>
	{
		return thenVal(promise, true);
	}

	public static function thenVal<T>(promise :Promise<Dynamic>, val :T) :Promise<T>
	{
		return promise.then(function(_) {
			return val;
		});
	}

	public static function traceJsonThenTrue(promise :Promise<Dynamic>) :Promise<Bool>
	{
		return promise.then(function(val) {
			trace(haxe.Json.stringify(val, null, '\t'));
			return true;
		});
	}

	public static function traceJson<T>(promise :Promise<T>) :Promise<T>
	{
		return promise.then(function(val) {
			trace(haxe.Json.stringify(val, null, '\t'));
			return val;
		});
	}

	public static function thenWait<T>(promise :Promise<T>, ?timems :Int = 50) :Promise<T>
	{
		var val :T;
		return promise.pipe(function(_) {
			val = _;
			var deferredPromise = new DeferredPromise();
			haxe.Timer.delay(function() {
				deferredPromise.resolve(true);
			}, timems);
			return deferredPromise.boundPromise;
		}).then(function(_) {
			return val;
		});
	}

	public static function pipeTrace<T>(promise :Promise<T>) :Promise<T>
	{
		return promise.then(function(val) {
			trace(val);
			return val;
		});
	}

	public static function traceThen<T>(promise :Promise<T>, s :String) :Promise<T>
	{
		return promise.then(function(val) {
			trace(s);
			return val;
		});
	}

	public static function pipeF<A,B>(promise :Promise<A>, f :A->Promise<B>) :Promise<B>
	{
		return promise.pipe(function(a :A) {
			return f(a);
		});
	}

	public static function pipeF0<A,B>(promise :Promise<A>, f :Void->Promise<B>) :Promise<B>
	{
		return promise.pipe(function(_ :A) {
			return f();
		});
	}

	public static function once<T>(p :Promise<Dynamic>, f :T->Void) :Void
	{
		var createdPromise :Promise<Dynamic> = null;
		createdPromise = p.then(function(val :T) {
			p.unlink(createdPromise);
			f(val);
		});
	}

	public static function chainPipePromises(p :Array<Void->Promise<Dynamic>>) :Promise<Array<Dynamic>>
	{
		if (p.length == 0) {
			return Promise.promise([]);
		}
		var promise = Promise.promise(null);
		var results = [];
		while (p.length > 0) {
			promise = chainPipeInternal(promise, p.shift())
				.then(function(val) {
					results.push(val);
					return val;
				});
		}
		return promise
			.then(function(_) {
				return results;
			});
	}

	static function chainPipeInternal(p :Promise<Dynamic>, f:Void->Promise<Dynamic>) :Promise<Dynamic>
	{
		return p.pipe(function(_) return f());
	}

	public static function connect<T>(p :AsyncBase<Dynamic>, f :T->Void) :Void->Void
	{
		var createdPromise :AsyncBase<Dynamic> = null;
		createdPromise = p.then(function(val :T) {
			return f(val);
		});
		return function() {
			p.unlink(createdPromise);
		};
	}

	public static function delay(?timems :Int = 50) :Promise<Bool>
	{
		var deferredPromise = new DeferredPromise();
		haxe.Timer.delay(function() {
			deferredPromise.resolve(true);
		}, timems);
		return deferredPromise.boundPromise;
	}

#if nodejs
	public static function streamToPromise(stream :js.node.stream.Readable<Dynamic>) :Promise<String>
	{
		var deferredPromise = new DeferredPromise();
		var result = '';
		stream.once(js.node.stream.Readable.ReadableEvent.Close, function() {
			deferredPromise.resolve(result);
		});
		stream.once(js.node.stream.Readable.ReadableEvent.End, function() {
			deferredPromise.resolve(result);
		});
		stream.once(js.node.stream.Readable.ReadableEvent.Error, function(err) {
			deferredPromise.boundPromise.reject(err);
		});
		stream.on(js.node.stream.Readable.ReadableEvent.Data, function(data :String) {
			result += data;
		});
		return deferredPromise.boundPromise;
	}
#end
}