package js.npm;

import js.npm.RedisClient;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

class RedisUtil
{
	/**
	 * CAREFUL!!!!!!!
	 */
	public static function deleteAllKeys(client :RedisClient) :Promise<Bool>
	{
		var deferred = new DeferredPromise();
		client.keys('*', function(err, keys) {
			var commands :Array<Array<String>> = [];
			for (key in keys) {
				commands.push(['del', key]);
			}
			client.multi(commands).exec(function(err, result) {
				if (err != null) {
					deferred.boundPromise.reject(err);
					return;
				}
				deferred.resolve(true);
			});
		});
		return deferred.boundPromise;
	}
}