package utils;

import promhx.Promise;
import promhx.PromiseQueue;
import promhx.deferred.DeferredPromise;

using promhx.PromiseTools;

class TestPromiseQueue extends haxe.unit.async.PromiseTest
{
	public function new() {}

	@timeout(30)
	public function testPromiseQueue()
	{
		var queue = new PromiseQueue();
		var p1;
		return Promise.promise(true)
			.pipe(function(_) {
				p1 = new DeferredPromise();
				queue.enqueue(function() return p1.boundPromise);
				var whenEmpty = queue.whenEmpty();
				assertFalse(whenEmpty.isResolved());
				return PromiseTools.delay(10)
					.pipe(function(_) {
					assertFalse(queue.isEmpty());
					assertFalse(whenEmpty.isResolved());
					return Promise.promise(true);
				})
				.pipe(function(_) {
					p1.resolve(true);
					return Promise.promise(true);
				})
				.pipe(function(_) {
					assertTrue(queue.isEmpty());
					return Promise.promise(true);
				});
			})
			.thenTrue();
	}
}