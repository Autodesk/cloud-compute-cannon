package ccc.compute.client.cli;

import ccc.compute.server.ProviderTools;
import ccc.compute.server.ProviderTools.*;

import haxe.Json;

import js.Node;
import js.node.Fs;
import js.node.Os;
import js.node.Path;
import js.npm.fsextended.FsExtended;
import js.npm.ssh2.Ssh;

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

	public static function getTestsProxy(rpcUrl :UrlString)
	{
		return ccc.compute.client.ProxyTools.getTestsProxy(rpcUrl);
	}

	public static function getHost() :Host
	{
		var configPath = findExistingServerConfigPath();
		var connection = configPath != null ? readServerConnection(configPath) : null;
		var host = if (hasServerHostInCLI()) {
			getServerHostInCLI();
		} else if (connection != null) {
			if (connection.server == null) {
				//This must be a local deployment
				return connection.host;
			} else {
				ProviderTools.getServerHost(new HostName(connection.server.hostPublic));
			}
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
		if (serverDef.server == null) {
			var hostName = serverDef.host.getHostname();
			var sshConfig = CliTools.getSSHConfigHostData(hostName);
			if (sshConfig != null) {
				serverDef.server = {
					id: null,
					hostPublic: new HostName(sshConfig.host),
					hostPrivate: null,
					ssh: sshConfig,
					docker: null
				};
				serverDef.host = new Host(serverDef.server.hostPublic, new Port(SERVER_DEFAULT_PORT));
			}
		}
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
		//Don't write the ssh info if it is in our ~/.ssh/config
		var hostName = config.host.getHostname();
		var sshConfig = CliTools.getSSHConfigHostData(hostName);
		if (sshConfig != null) {
			config.server = null;
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
		var program :js.npm.commander.Commander = js.Node.require('commander');
		if (Reflect.hasField(program, 'server')) {
			var host :Host = Reflect.field(program, 'server');
			return host;
		} else if (Reflect.hasField(program, 'public')) {
			return SERVER_PUBLIC_HOST;
		} else {
			return null;
		}
	}

	public static function isServerLocalDockerInstall(config :ServerConnectionBlob) :Bool
	{
		var host = getHostFromServerConfig(config);
		return host.startsWith('localhost');
	}

	/**
	 * Gets the address of a running cloudcomputecannon server.
	 * @param  config :ProviderConfig [description]
	 * @return        [description]
	 */
	public static function getServerHost(?path :String) :Host
	{
		var host :Host = getRawServerHost(path);
		if (host == null) {
			return host;
		}
		var hostName :HostName = host.getHostname();
		var sshConfig = getSSHConfigHostData(hostName);
		if (sshConfig != null) {
			host = new Host(new HostName(sshConfig.host), host.port());
		}
		return host;
	}

	static function getRawServerHost(?path :String) :Host
	{
		if (hasServerHostInCLI()) {
			return getServerHostInCLI();
		} else {
			var configPath = findExistingServerConfigPath(path);
			if (configPath != null) {
				var config = readServerConnection(configPath);
				if (config != null) {
					var host :Host = getHostFromServerConfig(config);
					return host;
				} else {
					throw 'configPath=$configPath is not null, but cannot get server connection from configuration';
				}
			} else {
				return SERVER_PUBLIC_HOST;
			}
		}
	}

	public static function getHostCheckSshConfig(host :HostName) :HostName
	{
		var sshConfig = getSSHConfigHostData(host);
		return sshConfig != null ? new HostName(sshConfig.host) : host;
	}

	inline public static function getHostFromServerConfig(config :ServerConnectionBlob) :Host
	{
		if (config.host != null) {
			return config.host;
		} else if (config.server != null && config.server.hostPublic != null) {
			return new Host(new HostName(config.server.hostPublic), new Port(SERVER_DEFAULT_PORT));
		} else if (config.server != null && config.server.ssh != null) {
			return new Host(new HostName(config.server.ssh.host), new Port(SERVER_DEFAULT_PORT));
		} else {
			return null;
		}
	}

	public static function getSSHConfigHostData(host :HostName, ?sshConfigData :String) :ConnectOptions
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