package promhx;

import haxe.Json;

import promhx.Deferred;
import promhx.Promise;
import promhx.CallbackPromise;

#if nodejs
import js.npm.RedisClient;
#else
typedef RedisClient = Dynamic;
#end

class RedisPromises
{
	inline public static function set(redis :RedisClient, key :String, val :String) :Promise<Bool>
	{
		var promise = new promhx.CallbackPromise();
		redis.set(key, val, promise.cb2);
		return promise;
	}

	inline public static function get(redis :RedisClient, key :String) :Promise<String>
	{
		var promise = new promhx.CallbackPromise();
		redis.get(key, promise.cb2);
		return promise;
	}

	inline public static function hget(redis :RedisClient, hashkey :String, hashField :String) :Promise<String>
	{
		var promise = new promhx.CallbackPromise();
		redis.hget(hashkey, hashField, promise.cb2);
		return promise;
	}

	inline public static function hkeys(redis :RedisClient, hashkey :String) :Promise<Array<Dynamic>>
	{
		var promise = new promhx.CallbackPromise();
		redis.hkeys(hashkey, promise.cb2);
		return promise;
	}

	inline public static function hset(redis :RedisClient, hashkey :String, hashField :String, val :String) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise<Int>();
		redis.hset(hashkey, hashField, val, promise.cb2);
		return promise;
	}

	inline public static function hexists(redis :RedisClient, hashkey :String, hashField :String) :Promise<Bool>
	{
		var promise = new promhx.CallbackPromise<Int>();
		redis.hexists(hashkey, hashField, promise.cb2);
		return promise
			.then(function(out :haxe.extern.EitherType<Int, Bool>) {
				return out == 1 || out == true;
			});
	}

	inline public static function hdel(redis :RedisClient, hashkey :String, hashField :String) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise<Int>();
		redis.hdel(hashkey, hashField, promise.cb2);
		return promise;
	}

	public static function getHashInt(redis :RedisClient, hashId :String, hashKey :String) :Promise<Int>
	{
		return hget(redis, hashId, hashKey)
			.then(function(val) {
				return Std.parseInt(val + '');
			});
	}

	public static function setHashInt(redis :RedisClient, hashId :String, hashKey :String, val :Int) :Promise<Int>
	{
		return hset(redis, hashId, hashKey, Std.string(val));
	}

	public static function getHashJson<T>(redis :RedisClient, hashId :String, hashKey :String) :Promise<T>
	{
		return hget(redis, hashId, hashKey)
			.then(function(val) {
				return Json.parse(val);
			});
	}

	public static function sadd(redis :RedisClient, set :String, members :Array<String>) :Promise<Int>
	{
		Assert.notNull(set);
		if (members == null || members.length == 0) {
			return Promise.promise(0);
		}
		members = members.concat([]);
		members.insert(0, set);
		var promise = new promhx.CallbackPromise();
		redis.sadd(members, promise.cb2);
		return promise;
	}

	public static function spop(redis :RedisClient, key :String) :Promise<Dynamic>
	{
		var promise = new promhx.CallbackPromise();
		redis.spop(key, promise.cb2);
		return promise;
	}

	public static function sismember(redis :RedisClient, key :String, member :String) :Promise<Bool>
	{
		var promise = new promhx.CallbackPromise();
		redis.sismember(key, member, promise.cb2);
		return promise
			.then(function(exists :Int) {
				return exists == 1;
			});
	}

	public static function srandmember(redis :RedisClient, key :String) :Promise<Dynamic>
	{
		var promise = new promhx.CallbackPromise();
		redis.srandmember(key, promise.cb2);
		return promise;
	}

	public static function smembers(redis :RedisClient, key :String) :Promise<Array<Dynamic>>
	{
		var promise = new promhx.CallbackPromise();
		redis.smembers(key, promise.cb2);
		return promise;
	}

	public static function zismember(redis :RedisClient, key :String, member :String) :Promise<Bool>
	{
		var promise = new promhx.CallbackPromise();
		redis.zscore(key, member, promise.cb2);
		return promise
			.then(function(score :Null<String>) {
				return score != null;
			});
	}

	public static function zadd(redis :RedisClient, key :String, score :Int, value :String) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		redis.zadd(key, score, value, promise.cb2);
		return promise;
	}

	public static function lpush(redis :RedisClient, key :String, value :String) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		redis.lpush(key, value, promise.cb2);
		return promise;
	}

	public static function del(redis :RedisClient, key :String) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		redis.del(key, promise.cb2);
		return promise;
	}

	public static function hmset(redis :RedisClient, key :String, fieldVals :Dynamic<String>) :Promise<String>
	{
		var promise = new promhx.CallbackPromise();
		redis.hmset(key, fieldVals, promise.cb2);
		return promise;
	}
}