package ccc.compute.cli;

import ccc.compute.Definitions;
import ccc.compute.Definitions.Constants.*;
import ccc.compute.server.ProviderTools;
import ccc.compute.server.ProviderTools.*;

import haxe.Json;

import js.Node;
import js.node.Os;
import js.node.Path;
import js.npm.FsExtended;

import promhx.Promise;
import promhx.RequestPromises;

import t9.abstracts.net.*;

using StringTools;

/**
 * CLI tools for client/server/proxies.
 */
class CliTools
{
	public static function getProxy(rpcUrl :UrlString)
	{
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.ServiceBatchCompute)
			.setConnection(new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(rpcUrl));
		return proxy;
	}

	public static function getHost() :Host
	{
		var configPath = findExistingServerConfigPath();
		var connection = configPath != null ? readServerConnection(configPath) : null;
		var host = if (hasServerHostInCLI()) {
			getServerHostInCLI();
		} else if (connection != null) {
			ProviderTools.getServerHost(new HostName(connection.server.ssh.host));
		} else {
			null;
		}
		return host;
	}

	/**
	 * Returns the path of the directory containing a .cloudcomputecannon
	 * child folder that contains a server.json file.
	 * Parent directories will be searched until a file is found, or null.
	 * @param  ?path :String       [description]
	 * @return       [description]
	 */
	public static function findExistingServerConfigPath(?path :String) :String
	{
		path = path == null ? Node.process.cwd() : path;
		if (!path.startsWith(ROOT)) {
			path = Path.join(Node.process.cwd(), path);
		}
		var serverJsonPath = Path.join(path, LOCAL_CONFIG_DIR, SERVER_CONNECTION_FILE);
		if (FsExtended.existsSync(serverJsonPath)) {
			return path;
		} else {
			if (path == ROOT) {
				return null;
			} else {
				if (Path.dirname(path) != null) {
					return findExistingServerConfigPath(Path.dirname(path));
				} else {
					return null;
				}
			}
		}
	}

	/**
	 * This path (and parents) will be searched for a .cloudcomputecannon child.
	 * @param  ?path :String       [description]
	 * @return       [description]
	 */
	public static function readServerConnection(configPath :String) :ServerConnectionBlob
	{
		var serverJsonPath = buildServerConnectionPath(configPath);
		var serverDef :ServerConnectionBlob = Json.parse(FsExtended.readFileSync(serverJsonPath, {}));
		return serverDef;
	}

	public static function buildServerConnectionPath(configPath :String) :String
	{
		return Path.join(configPath, LOCAL_CONFIG_DIR, SERVER_CONNECTION_FILE);
	}

	public static function isServerConnection(configPath :String) :Bool
	{
		var serverJsonPath = buildServerConnectionPath(configPath);
		return FsExtended.existsSync(serverJsonPath);
	}

	public static function writeServerConnection(config :ServerConnectionBlob, ?path :String)
	{
		if (path == null) {
			path = js.Node.process.cwd();
		}
		var configString = Json.stringify(config, null, '\t');
		FsExtended.ensureDirSync(Path.join(path, LOCAL_CONFIG_DIR));
		FsExtended.writeFileSync(Path.join(path, LOCAL_CONFIG_DIR, SERVER_CONNECTION_FILE), configString);
	}

	public static function deleteServerConnection(path :String)
	{
		var configPath = buildServerConnectionPath(path);
		FsExtended.unlinkSync(configPath);
	}

	public static function hasServerHostInCLI() :Bool
	{
		return getServerHostInCLI() != null;
	}

	public static function getServerHostInCLI() :Host
	{
		var program :js.npm.Commander = js.Node.require('commander');
		if (Reflect.hasField(program, 'host')) {
			var host :Host = Reflect.field(program, 'host');
			return host;
		} else {
			return null;
		}
	}

	/**
	 * Gets the address of a running cloudcomputecannon server.
	 * @param  config :ProviderConfig [description]
	 * @return        [description]
	 */
	public static function getServerHost(?path :String) :Promise<Host>
	{
		if (hasServerHostInCLI()) {
			return Promise.promise(getServerHostInCLI());
		} else {
			var configPath = findExistingServerConfigPath(path);
			if (configPath != null) {
				var config = readServerConnection(configPath);
				if (config != null) {
					var host :Host = getHostFromServerConfig(config);
					return Promise.promise(host);
				} else {
					return Promise.promise(null);
				}
			} else {
				return Promise.promise(null);
			}

			// var config = readServerConnection(path);
			// if (config != null) {
			// 	var host :Host = getHostFromServerConfig(config.data);
			// 	return Promise.promise(host);
			// } else {
			// 	return Promise.promise(null);
			// }
			// return CliTools.isLocalServer()	
			// 	.pipe(function(isLocal) {
			// 		if (isLocal) {
			// 			trace('returning localhost for server');
			// 			var localhost :Host = 'localhost:${Constants.SERVER_DEFAULT_PORT}';
			// 			return Promise.promise(localhost);
			// 		} else {
			// 			var config = InitConfigTools.ohGodGetConfigFromSomewhere();
			// 			return ensureRemoteServer(config.providers[0])//Check for saved credentials on disk
			// 				.then(function(serverBlob) {
			// 					var serverHost :Host = serverBlob.server.ssh.host + ':' + SERVER_PORT;
			// 					return serverHost;
			// 				});
			// 		}
			// 	});
		}
	}

	inline public static function getHostFromServerConfig(config :ServerConnectionBlob) :Host
	{
		return config.server.ssh.host + ':' + SERVER_DEFAULT_PORT;
	}

	// public static function isLocalServer() :Promise<Bool>
	// {
	// 	return serverCheck('localhost:${Constants.SERVER_DEFAULT_PORT}');
	// }

}