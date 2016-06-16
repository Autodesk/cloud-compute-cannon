package ccc.compute.client.cli;

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
	public static function findExistingServerConfigPath(?path :CLIServerPathRoot) :CLIServerPathRoot
	{
		path = path == null ? Node.process.cwd() : path;
		var pathString = path.toString();
		if (!pathString.startsWith(ROOT)) {
			path = Path.join(Node.process.cwd(), pathString);
		}
		if (FsExtended.existsSync(path.getServerJsonConfigPath())) {
			return path;
		} else {
			if (path == ROOT) {
				return null;
			} else {
				if (Path.dirname(pathString) != null) {
					return findExistingServerConfigPath(Path.dirname(pathString));
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
	public static function readServerConnection(configPath :CLIServerPathRoot) :ServerConnectionBlob
	{
		var serverDef :ServerConnectionBlob = Json.parse(FsExtended.readFileSync(configPath.getServerJsonConfigPath(), {}));
		return serverDef;
	}

	public static function isServerConnection(configPath :CLIServerPathRoot) :Bool
	{
		return FsExtended.existsSync(configPath.getServerJsonConfigPath());
	}

	public static function writeServerConnection(config :ServerConnectionBlob, ?path :CLIServerPathRoot)
	{
		if (path == null) {
			path = js.Node.process.cwd();
		}
		var configString = Json.stringify(config, null, '\t');
		FsExtended.ensureDirSync(path.getServerJsonConfigPathDir());
		FsExtended.writeFileSync(path.getServerJsonConfigPath(), configString);
	}

	public static function deleteServerConnection(path :CLIServerPathRoot)
	{
		FsExtended.unlinkSync(path.getServerJsonConfigPath());
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
		if (config.host != null) {
			return config.host + ':' + SERVER_DEFAULT_PORT;
		} else if (config.server != null && config.server.ssh != null) {
			return config.server.ssh.host + ':' + SERVER_DEFAULT_PORT;
		} else {
			return null;
		}
	}

	// public static function isLocalServer() :Promise<Bool>
	// {
	// 	return serverCheck('localhost:${Constants.SERVER_DEFAULT_PORT}');
	// }

}