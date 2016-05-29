package util;

/**
 * Typedefs and data structures for interacting
 * with the shared Redis store. State is stored
 * in the Redis instance and not in the servers
 * to allow scaling.
 */

import haxe.Json;

import js.npm.RedisClient;

import promhx.Promise;
import promhx.Stream;
import promhx.RedisPromises;
import promhx.deferred.DeferredPromise;
import promhx.deferred.DeferredStream;

@:enum
abstract PubSubChannel(String)
{
    var AvailableInstances = 'compute_instances';
}

typedef WorkerInstance=Dynamic;

typedef RedisConnection = {
	@:optional var port :Int;
	@:optional var address :String;
	@:optional var options :Dynamic;
}

class RedisTools
{
	public static function createStreamFromHash<T>(redis :RedisClient, channelKey :String, hashKey :String, hashField :String) :Stream<T>
	{
		return createStreamCustom(redis, channelKey, function(_) {
			return cast RedisPromises.hget(redis, hashKey, hashField);
		});
	}

	public static function createJsonStreamFromHash<T>(redis :RedisClient, channelKey :String, hashKey :String, hashField :String) :Stream<T>
	{
		return createStreamCustom(redis, channelKey, function(_) {
			return RedisPromises.hget(redis, hashKey, hashField)
				.then(function(s) {
					return Json.parse(s);
				});
		});
	}

	public static function createStreamCustom<T>(redis :RedisClient, channelKey :String, ?getter :Dynamic->Promise<T>, ?usePatterns :Bool = false) :Stream<T>
	{
		var subscribeClient = RedisClient.createClient(redis.connectionOption.port, redis.connectionOption.host);
		return createStreamCustomInternal(subscribeClient, channelKey, getter, usePatterns);
	}

	public static function createStreamCustomInternal<T>(subscribeClient :RedisClient, channelKey :String, ?getter :Dynamic->Promise<T>, ?usePatterns :Bool = false) :Stream<T>
	{
		Assert.notNull(subscribeClient);
		Assert.notNull(channelKey);

		var deferred = new promhx.deferred.DeferredStream<T>();
		var unsubscribed = false;

		function getAndSend(message :Dynamic) {
			if (!unsubscribed) {
				if (getter != null) {
					getter(message)
						.then(function(val :T) {
							if (val != null) {
								deferred.resolve(val);
							}
						});
				} else {
					deferred.resolve(message);
				}
			}
		}

		if (usePatterns) {
			subscribeClient.on(RedisClient.EVENT_PMESSAGE, function (pattern, channel, message) {
				if (pattern == channelKey) {
					getAndSend(message);
				}
			});
		} else {
			subscribeClient.on(RedisClient.EVENT_MESSAGE, function (channel, message) {
				if (channel == channelKey) {
					getAndSend(message);
				}
			});
		}

		if (usePatterns) {
			subscribeClient.psubscribe(channelKey);
		} else {
			subscribeClient.subscribe(channelKey);
		}

		deferred.boundStream.endThen(function(_) {
			unsubscribed = true;
			if (usePatterns) {
				subscribeClient.punsubscribe(channelKey);
			} else {
				subscribeClient.unsubscribe(channelKey);
			}
			subscribeClient.quit();
		});

		subscribeClient.on(RedisEvent.Error, function(err) {
			Log.error({error:err, system:'redis', event:RedisEvent.Error, message:'subscribeClient'});
			subscribeClient.once(RedisEvent.Connect, getAndSend.bind(null));
		});

		//Call immediately after subscribing, and again after 100ms, since it takes a while to connect
		getAndSend(null);
		subscribeClient.once(RedisClient.EVENT_SUBSCRIBE, function (channel, count) {
			if (!unsubscribed) {
				getAndSend(null);
			}
		});
		return deferred.boundStream;
	}

	public static function createStream<T>(redis :RedisClient, key :String) :Stream<T>
	{
		return createStreamCustom(redis, key);
		// var client = RedisClient.createClient(redis.port, redis.host);
		// return createStreamInternal(client, key);
	}

	public static function createPublishStream<T>(redis :RedisClient, channelKey :String, ?usePatterns :Bool = false) :Stream<T>
	{
		return createStreamCustom(redis, channelKey, function(message) return message, usePatterns);

		// var subscribeClient = RedisClient.createClient(redis.connectionOption.port, redis.connectionOption.host);
		// var deferred = new promhx.deferred.DeferredStream<T>();
		// if (usePatterns) {
		// 	subscribeClient.on(RedisClient.EVENT_PMESSAGE, function (pattern, channel, message) {
		// 		if (pattern == channelKey) {
		// 			deferred.resolve(message);
		// 		}
		// 	});
		// } else {
		// 	subscribeClient.on(RedisClient.EVENT_MESSAGE, function (channel, message) {
		// 		if (channel == channelKey) {
		// 			deferred.resolve(message);
		// 		}
		// 	});
		// }

		// if (usePatterns) {
		// 	subscribeClient.psubscribe(channelKey);
		// } else {
		// 	subscribeClient.subscribe(channelKey);
		// }

		// deferred.boundStream.endThen(function(_) {
		// 	if (usePatterns) {
		// 		subscribeClient.punsubscribe(channelKey);
		// 	} else {
		// 		subscribeClient.unsubscribe(channelKey);
		// 	}
		// 	subscribeClient.quit();
		// });

		// return deferred.boundStream;
	}

	// public static function createStreamInternal<T>(redis :RedisClient, key :String, ?usePatterns :Bool = false) :Stream<T>
	// {
	// 	var deferred = new promhx.deferred.DeferredStream<T>();
	// 	redis.once(RedisClient.EVENT_SUBSCRIBE, function (channel, count) {
	// 		// Log.info('Streaming $key');
	// 	});
	// 	redis.on(RedisClient.EVENT_MESSAGE, function (channel, message) {
	// 		if (channel == key) {
	// 			deferred.resolve(message);
	// 		}
	// 	});
	// 	redis.get(key, function(err :Dynamic, val) {
	// 		if (err != null) {
	// 			deferred.throwError(err);
	// 			return;
	// 		}
	// 		deferred.resolve(cast val);
	// 	});
	// 	redis.subscribe(key);

	// 	deferred.boundStream.endThen(function(_) {
	// 		redis.unsubscribe(key);
	// 		redis.quit();
	// 	});

	// 	return deferred.boundStream;
	// }

	public static function sendStreamedValue(client :RedisClient, key :String, val :Dynamic) :Promise<Bool>
	{
		var deferred = new promhx.deferred.DeferredPromise<Bool>();
		client.set(key, val, function(err, success) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			client.publish(key, val);
			deferred.resolve(true);
		});
		return deferred.boundPromise;
	}

	public static function createJsonStream<T>(redis :RedisClient, channelKey :String, ?redisKey :String, ?usePatterns :Bool = false #if debug ,?pos:haxe.PosInfos #end) :Stream<T>
	{
		if (redisKey == null) {
			redisKey = channelKey;
		}
		return createStreamCustom(redis, channelKey, function(message) {
				var promise = new promhx.deferred.DeferredPromise<T>(#if debug pos #end);
				redis.get(redisKey, function(err :Dynamic, val) {
					if (err != null) {
						promise.boundPromise.reject(err);
						return;
					}
					promise.resolve(Json.parse(val));
				});
				return promise.boundPromise;
		}, usePatterns);
	}

	public static function sendJsonStreamedValue(client :RedisClient, key :String, val :Dynamic) :Promise<Bool>
	{
		var deferred = new promhx.deferred.DeferredPromise<Bool>();
		var s = Json.stringify(val);
		client.set(key, s, function(err, success) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			client.publish(key, s);
			deferred.resolve(true);
		});
		return deferred.boundPromise;
	}
}