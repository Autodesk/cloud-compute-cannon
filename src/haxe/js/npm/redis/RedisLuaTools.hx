package js.npm.redis;

import js.npm.RedisClient;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

using Lambda;
using StringTools;

typedef ScriptId = {
	var id :String;
	var sha1 :String;
}

class RedisLuaTools
{
	/**
	 * Load Lua scripts into the redis instance so you can
	 * call scripts by the SHA1 instead of sending the entire
	 * script over the wire with every call.
	 * @param  client :RedisClient  [description]
	 * @return        Map<ScriptId, Script SHA1>
	 */
	public static function initLuaScripts(client :RedisClient, scripts :Map<String, String>) :Promise<Map<String, String>>
	{
		var deferred = new DeferredPromise();

		var commands = [];
		var scriptIds = [];

		for (scriptId in scripts.keys()) {
			scriptIds.push(scriptId);
			commands.push(['script', 'load', scripts[scriptId]]);
		}
		client
			.multi(commands)
			.exec(function(err, result :Array<Dynamic>) {
				if (err != null) {
					deferred.boundPromise.reject(err);
					return;
				}
				var scriptShas :Array<String> = result.map(Std.string);
				var scriptIdToSha1 = new Map<String, String>();
				for (i in 0...scriptShas.length) {
					if (scriptShas[i].startsWith('Err') || scriptShas[i].startsWith('ERR')) {
						deferred.boundPromise.reject(scriptIds[i] + '=' + scriptShas[i] + '\n' + scripts[scriptIds[i]].split('\n').mapi(function(i, e) return i + '\t' + e).join('\n'));
						return;
					}
					scriptIdToSha1[scriptIds[i]] = scriptShas[i];
				}
				deferred.resolve(scriptIdToSha1);
			});

		return deferred.boundPromise;
	}

	public static function evaluateLuaScript<T>(client :RedisClient, scriptId :String, ?redisKeys :Array<String>, ?args :Array<Dynamic>, ?scriptIdsToName:Map<String, String>, ?scriptIdsToScript:Map<String, String>) :Promise<T>
	{
		Assert.notNull(client);
		Assert.notNull(scriptId);
		var deferred = new DeferredPromise();
		var command :Array<Dynamic> = [scriptId, redisKeys != null ? redisKeys.length : 0];
		if (redisKeys != null && redisKeys.length > 0) {
			command = command.concat(redisKeys);
		}
		if (args != null && args.length > 0) {
			command = command.concat(args);
		}
		client.evalsha(command, function(err :Dynamic, result :Dynamic) {
			if (err != null) {
				//If we've mapped the scriptId to the script sha1, the error message can refer to the script id
				if (scriptIdsToName != null && scriptIdsToName.exists(scriptId)) {
					err = Std.string(err);
					err = err.replace('f_' + scriptId, scriptIdsToName[scriptId]);
				}

				if (scriptIdsToScript != null) {
					var r = ~/.*user_script:([0-9]+).*/;
					if (r.match(err)) {
						var lineNumberMatch = r.matched(1);
						if (lineNumberMatch != null) {
							var lineNumber = Std.parseInt(lineNumberMatch);
							var script = scriptIdsToScript[scriptIdsToName[scriptId]];
							if (script != null) {
								var lines = script.split('\n');
								var errorLines = '';
								var startingAhead = 0;//Std.int(Math.floor(Math.max(0, lineNumber - 20)));
								for (ln in startingAhead...lineNumber) {
									errorLines += lines[ln] + '\n';
								}
								err += '\nProblem line (last line):\n' + errorLines;
								// var line = script.split('\n')[lineNumber - 1];
								// if (line != null) {
								// 	err += '\nProblem line:\n' + line;
								// }
							}
						}
					}
				}

				Log.error(err);
				deferred.boundPromise.reject(err);
				return;
			}
			deferred.resolve(result);
		});
		return deferred.boundPromise;
	}

	/**
	 * Empty arrays can be returned as objects, which have no length.
	 * It's annoying.
	 * @param  obj :Dynamic      [description]
	 * @return     [description]
	 */
	public static function isArrayObjectEmpty(obj :Dynamic) :Bool
	{
		if (obj == null) {
			return true;
		} else {
			return Std.is(obj, Array) ? obj.length == 0 : true;
		}
	}
}