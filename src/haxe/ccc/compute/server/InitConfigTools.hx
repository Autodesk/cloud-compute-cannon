package ccc.compute.server;

/**
 * A set of static functions to do heavy lifting for
 * a) getting configuration from config files, env variables, a redis server
 * b) possibly reloading if configurations change
 * c) ?
 */

import js.node.Fs;
import js.npm.PkgCloud;
import js.npm.RedisClient;
import js.npm.PkgCloud.ClientOptionsAmazon;

import ccc.compute.server.ConnectionToolsDocker;

import yaml.Yaml;

class InitConfigTools
{
	public static function getConfig() :ServiceConfiguration
	{
		var env = Node.process.env;
		var config :ServiceConfiguration = null;
		Log.debug('ENV_VAR_COMPUTE_CONFIG_PATH=${Reflect.field(env, ENV_VAR_COMPUTE_CONFIG_PATH)}');
		var CONFIG_PATH :String = Reflect.hasField(env, ENV_VAR_COMPUTE_CONFIG_PATH) && Reflect.field(env, ENV_VAR_COMPUTE_CONFIG_PATH) != "" ? Reflect.field(env, ENV_VAR_COMPUTE_CONFIG_PATH) : SERVER_MOUNTED_CONFIG_FILE_DEFAULT;
		Log.debug({'CONFIG_PATH':CONFIG_PATH});
		if (Reflect.field(env, ENV_CLIENT_DEPLOYMENT) == 'true') {
			Log.warn('Loading config from mounted file=$CONFIG_PATH');
			config = InitConfigTools.getConfigFromFile(CONFIG_PATH);
		} else {
			config = InitConfigTools.ohGodGetConfigFromSomewhere(CONFIG_PATH);
		}
		return config;
	}

	public static function getDefaultConfig() :ServiceConfiguration
	{
		Assert.notNull(haxe.Resource.getString('etc/config/serverconfig.template.yml'), 'getDefaultConfig() Missing Resource=etc/config/serverconfig.template.yml');
		return parseConfig(haxe.Resource.getString('etc/config/serverconfig.template.yml'));
	}

	inline public static function parseConfig(s :String) :ServiceConfiguration
	{
		// trace('s=${s}');
		return Yaml.parse(s, DEFAULT_YAML_OPTIONS);
	}

	public static function initRedisServices(redis :RedisClient) :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				return ComputeQueue.init(redis);
			})
			.pipe(function(_) {
				return InstancePool.init(redis);
			})
			.pipe(function(_) {
				var jobStats :JobStats = redis;
				return jobStats.init();
			});
	}

	public static function initAll(redis :RedisClient) :Promise<Void->Void> //Shutdown callback
	{
		var disposers :Array<Void->Void> = [];
		var dispose = function() {
			for (f in disposers) {
				f();
			}
		}

		return Promise.promise(true)
			.pipe(function(_) {
				return initRedisServices(redis);
			})
			.pipe(function(_) {
				//Set up the job queue monitor for every second. Move this to a parameter eventually
				//This removes jobs that have been working too long, it puts them back in the queue.
				disposers.push(ComputeQueue.startPoll(redis));
				return Promise.promise(true);
			})
			.then(function(_) {
				return dispose;
			});
	}

	public static function ohGodGetConfigFromSomewhere(?path :String) :ServiceConfiguration
	{
		var env = js.Node.process.env;
		if (Reflect.hasField(env, ENV_VAR_COMPUTE_CONFIG) && Reflect.field(env, ENV_VAR_COMPUTE_CONFIG) != null && Reflect.field(env, ENV_VAR_COMPUTE_CONFIG) != '') {
			Log.warn({server_status:'get_config', message:'Getting config from $ENV_VAR_COMPUTE_CONFIG env var'});
			return Yaml.parse(Reflect.field(env, ENV_VAR_COMPUTE_CONFIG), DEFAULT_YAML_OPTIONS);
		} else {
			Log.debug({server_status:'get_config', message:'no $ENV_VAR_COMPUTE_CONFIG in env, path=$path'});
			if (path != null) {
				//This will throw an error if it doesnt' exist
				try {
					Fs.statSync(path);
					Log.warn('Loading config from file=$path');
					return getConfigFromFile(path);
				} catch (_ :Dynamic) {
					//Swallow errors
					Log.debug({server_status:'get_config', message:'path=$path does not exist'});
				}
			}
			Log.debug({server_status:'get_config', message:'using default config'});
			Log.warn('Loading default config');
			return getDefaultConfig();
		}
	}

	public static function getConfigFromEnv() :ServiceConfiguration
	{
		var env = Node.process.env;
		if (Reflect.hasField(env, ENV_VAR_COMPUTE_CONFIG) && Reflect.field(env, ENV_VAR_COMPUTE_CONFIG) != null && Reflect.field(env, ENV_VAR_COMPUTE_CONFIG) != '') {
			return Yaml.parse(Reflect.field(env, ENV_VAR_COMPUTE_CONFIG), DEFAULT_YAML_OPTIONS);
		} else {
			return null;
		}
	}

	public static function isPkgCloudConfigured(config :ServiceConfiguration) :Bool
	{
		return config.providers != null && config.providers.exists(function(e) {
			return Std.string(e.type) == "PkgCloud";
		});
	}

	// public static function getConfig(?path :String) :ServiceConfiguration
	// {
	// 	var config = path != null ? getConfigFromFile(path) : cast({}:ServiceConfiguration);
	// 	config = getEnvironmentalConfig(config);
	// 	return config;
	// }

	public static function getConfigFromFile(path :String) :ServiceConfiguration
	{
		var fileString;
		try {
			fileString = Fs.readFileSync(path, {encoding:'utf8'});
		} catch(err :Dynamic) {
			Log.warn('No config file "$path"');
			return {};
		}

		if (path.endsWith('.yaml') || path.endsWith('.yml')) {
			return Yaml.parse(fileString, DEFAULT_YAML_OPTIONS);
		} else {
			return Json.parse(fileString);
		}
	}

	public static function getEnvironmentalConfig(?existing :ServiceConfiguration) :ServiceConfiguration
	{
		existing = existing == null ? {} : existing;
		for (f in Reflect.fields(js.Node.process.env)) {
			var val = Reflect.field(js.Node.process.env, f);
			var tokens = f.split('__');
			var obj = existing;
			while (tokens.length > 1) {
				var match = null;
				if (!Reflect.hasField(obj, tokens[0])) {
					Reflect.setField(obj, tokens[0], {});
				}
				obj = Reflect.field(obj, tokens[0]);
				tokens.shift();
			}
			Reflect.setField(obj, tokens[0], val);
		}
		return existing;
	}

	public static function configToEnvVars(config :ServiceConfiguration) :Dynamic<String>
	{
		var result :Dynamic<String> = {};
		var build = null;
		build = function(prefix :String, obj :Dynamic) {
			prefix = prefix == null ? "" : prefix + '__';
			for (f in Reflect.fields(obj)) {
				var val = Reflect.field(obj, f);
				if (untyped __typeof__(val) == 'object') {
					build(prefix + f, val);
				} else {
					Reflect.setField(result, prefix + f, val);
				}
			}
		}
		build(null, config);
		return result;
	}

	private static function readConfigFile(path :String) :Dynamic<String>
	{
		var fileString;
		try {
			fileString = Fs.readFileSync(path, {encoding:'utf8'});
		} catch(err :Dynamic) {
			Log.warn('No config file "$path"');
			return {};
		}

		if (path.endsWith('.yaml') || path.endsWith('.yml')) {
			return Yaml.parse(fileString, DEFAULT_YAML_OPTIONS);
		} else if (path.endsWith('.json')) {
			return Json.parse(fileString);
		} else {
			try {
				return Yaml.parse(fileString, DEFAULT_YAML_OPTIONS);
			} catch(err :Dynamic) {
				Log.error(err);
				return return Json.parse(fileString);
			}
		}
	}

	public static function getAmazonCredentials(?existing :ClientOptionsAmazon, ?path :String) :ClientOptionsAmazon
	{
		if (existing == null) {
			existing = {
				provider: ProviderType.amazon,
				keyId: null,
				key: null,
				region: null
			};
		}

		// fill in any creds from the file if they aren't set in the exisiting configuraiton
		if (path != null) {
			var config :Dynamic<String> = readConfigFile(path);
			for (f in Reflect.fields(existing)) {
				var val :String = Reflect.field(existing, f);
				var configValue :String = Reflect.field(config, f);
				if ((val == null) && (configValue != null)) {
					Reflect.setField(existing, f, configValue);
				}
			}
		}

		if (existing.provider != null) {
			Assert.that(ProviderType.amazon == existing.provider);
		} else {
			existing.provider = ProviderType.amazon;
		}

		return existing;
	}

	public static var DEFAULT_YAML_OPTIONS = new yaml.Parser.ParserOptions().useObjects().strictMode(false);
}