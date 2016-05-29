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

import util.RedisTools;

using StringTools;

class TestRedisMock extends haxe.unit.async.PromiseTest
{
	public function new() {}

	public function testRedisMock()
	{
		var deferred = new DeferredPromise<Bool>();

		var redis = js.npm.RedisClientMock.createClient();
		var testchannel = 'testchannel';
		redis.on(RedisClient.EVENT_MESSAGE, function(channel, message) {
			if (channel == testchannel) {
				redis.end();
				deferred.resolve(true);
			}
		});
		redis.on(RedisClient.EVENT_SUBSCRIBE, function(channel, message) {
			redis.publish(testchannel, 'testmessage');
		});
		redis.subscribe(testchannel);

		return deferred.boundPromise;
	}

	public function testRedisStream()
	{
		var deferred = new DeferredPromise<Bool>();

		var conn = function() {
			return js.npm.RedisClientMock.createClient();
		}

		var key = 'some_stream_key';

		var sendClient = js.npm.RedisClientMock.createClient();

		var stream :Stream<String> = RedisTools.createStreamCustomInternal(sendClient, key);

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
				deferred.resolve(true);
			}
		});

		RedisTools.sendStreamedValue(sendClient, key, val1)
			.then(function(_) {
				RedisTools.sendStreamedValue(sendClient, key, val2);
			});

		return deferred.boundPromise;
	}
}