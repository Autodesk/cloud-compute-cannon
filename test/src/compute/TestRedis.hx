 package compute;

import haxe.Json;
import haxe.unit.async.PromiseTest;

import js.Node;
import js.node.Path;
import js.node.Fs;
import js.npm.RedisClient;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.PromiseTools;

import util.RedisTools;
import ccc.compute.*;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;

typedef TestType = {
	var id :JobId;
	var stuff :String;
}

class TestRedis extends haxe.unit.async.PromiseTest
{
	public function new() {}

	override public function setup() :Null<Promise<Bool>>
	{
		return ConnectionToolsRedis.getRedisClient()
			.pipe(function(redis) {
				return js.npm.RedisUtil.deleteAllKeys(redis);
			});
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		return ConnectionToolsRedis.getRedisClient()
			.pipe(function(redis) {
				return js.npm.RedisUtil.deleteAllKeys(redis);
			});
	}

	public function testRedisPubsub()
	{
		return Promise.whenAll([ConnectionToolsRedis.getRedisClient(), ConnectionToolsRedis.getRedisClient()])
			.pipe(function(redises :Array<RedisClient>) {
				var deferred = new DeferredPromise<Bool>();
				var redis = redises[0];
				var sender = redises[1];
				var testchannel = 'testchannel' + Math.floor(Math.random() * 10000000);
				redis.on(RedisClient.EVENT_MESSAGE, function(channel, message) {
					if (channel == testchannel) {
						sender.del(testchannel, function(_, _) {});
						redis.end();
						deferred.resolve(true);
					}
				});
				redis.on(RedisClient.EVENT_SUBSCRIBE, function(channel, message) {
					sender.publish(testchannel, 'testmessage');
				});
				redis.subscribe(testchannel);

				return deferred.boundPromise;
			});
	}

	@timeout(100)
	public function testRedisStream()
	{
		trace('testRedisStream');
		return Promise.whenAll([ConnectionToolsRedis.getRedisClient(), ConnectionToolsRedis.getRedisClient()])
			.pipe(function(redises :Array<RedisClient>) {
				var deferred = new DeferredPromise<Bool>();

				var sendClient = redises[0];

				var key = 'some_stream_key' + Math.floor(Math.random() * 10000000);

				var stream :Stream<String> = RedisTools.createStream(redises[1], key);

				var val1 = 'testVal1';
				var val2 = 'testVal2';

				var recieved1 = false;
				var recieved2 = false;

				stream.then(function(val) {
					if (val == val1) {
						recieved1 = true;
					}
					if (val == val2) {
						recieved2 = true;
					}
					if (recieved1 && recieved2) {
						sendClient.del(key, function(_, _) {
							deferred.resolve(true);
						});
					}
				});

				Promise.promise(true)
					.thenWait(50)//Wait until the stream is listening. This is a weakness here, but our use case does not require getting prior values
					.then(function(_) {
						RedisTools.sendStreamedValue(sendClient, key, val1)
						.then(function(_) {
							RedisTools.sendStreamedValue(sendClient, key, val2);
						});
					});

				return deferred.boundPromise;
			});
	}
}