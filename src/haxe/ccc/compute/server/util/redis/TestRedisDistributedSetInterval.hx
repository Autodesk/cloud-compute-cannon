package ccc.compute.server.util.redis;

class TestRedisDistributedSetInterval extends haxe.unit.async.PromiseTest
{
	@inject public var _injector :Injector;

	public function new() {}

	@timeout(5000)
	public function testRedisDistributedSetInterval() :Promise<Bool>
	{
		var timers :Array<RedisDistributedSetInterval> = [];
		var taskId = 'testTaskId' + Std.int((Math.random() * 100000));
		return Promise.promise(true)
			.pipe(function(_) {

				var interval = 500;
				var timerCount = 12;
				var handlerCalledCount = 0;

				var handler = function() {
					handlerCalledCount++;
				}

				for (i in 0...timerCount) {
					var timer = new RedisDistributedSetInterval(taskId, interval, handler);
					_injector.injectInto(timer);
					timers.push(timer);
				}

				var promise = new DeferredPromise();

				Node.setTimeout(function() {
					promise.resolve(handlerCalledCount == 3);
				}, 1900);

				return promise.boundPromise;
			})
			.errorPipe(function(err) {
				Log.error(err);
				return Promise.promise(false);
			})
			.then(function(result) {
				var redis :RedisClient = _injector.getValue(RedisClient);
				redis.hdel(RedisDistributedSetInterval.REDIS_KEY_HASH_DISTRIBUTED_TASKS, taskId, function(err:Dynamic, r:Int){});
				for (t in timers) {
					t.dispose();
				}
				return result;
			});
	}
}