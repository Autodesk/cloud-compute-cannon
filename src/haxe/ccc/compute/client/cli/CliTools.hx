package ccc.compute.client.cli;

import ccc.compute.server.ProviderTools;
import ccc.compute.server.ProviderTools.*;

import haxe.Json;

import js.Node;
import js.node.Fs;
import js.node.Os;
import js.node.Path;
import js.npm.FsExtended;
import js.npm.Ssh;

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
		return ccc.compute.client.ProxyTools.getProxy(rpcUrl);
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
		if (Reflect.hasField(program, 'server')) {
			var host :Host = Reflect.field(program, 'server');
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

	public static function getSSHConfigHostData(host :String, ?sshConfigData :String) :ConnectOptions
	{
		try {
			if (sshConfigData == null) {
				var sshConfigPath = Path.join(untyped __js__('require("os").homedir()'), '.ssh/config');
				sshConfigData = Fs.readFileSync(sshConfigPath, {encoding:'utf8'});
			}
			var lines = sshConfigData.split('\n');
			var foundEntry = false;
			var i = 0;
			var hostName :HostName = null;
			var key = null;
			var username = null;
			var hostRegExStr = '\\s?Host\\s+([a-zA-Z_0-9]+)';
			while (i < lines.length) {
				if (foundEntry) {
					//Check if we're out
					var hostRegEx = new EReg(hostRegExStr, '');//~/\s+Host\s+([a-zA-Z_0-9]+).*/;
					if (hostRegEx.match(lines[i])) {
						break;
					} else {
						if (lines[i].trim().startsWith('User')) {
							username = lines[i].replace('User', '').trim();
						} else if (lines[i].trim().startsWith('IdentityFile')) {
							var identityFile = lines[i].replace('IdentityFile', '').trim();
							if (identityFile.startsWith('~')) {
								identityFile = identityFile.replace('~', untyped __js__('require("os").homedir()'));
							}
							key = Fs.readFileSync(identityFile, {encoding:'utf8'});
						} else if (lines[i].trim().startsWith('HostName')) {
							hostName = new HostName(lines[i].replace('HostName', '').trim());
						}
					}
				} else {
					var hostRegEx = new EReg(hostRegExStr, '');
					if (hostRegEx.match(lines[i])) {
					}
					if (hostRegEx.match(lines[i]) && hostRegEx.matched(1) == host) {
						foundEntry = true;
					}
				}
				i++;
			}
			return hostName != null ? {host:hostName, privateKey:key, username:username} : null;
		} catch(err :Dynamic) {
			trace('err=${err}');
			return null;
		}
	}
}