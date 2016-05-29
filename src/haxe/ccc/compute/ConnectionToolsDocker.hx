package ccc.compute;

import js.Node;
import js.node.Fs;
import js.node.Path;
import js.npm.Docker;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

import t9.abstracts.net.*;

using promhx.PromiseTools;
using Lambda;
using StringTools;

class ConnectionToolsDocker
{
	public inline static var DOCKER_HOST = 'DOCKER_HOST'; //Looks like: tcp://192.168.59.103:2376
	public inline static var DOCKER_TLS_VERIFY = 'DOCKER_TLS_VERIFY';
	public inline static var DOCKER_CERT_PATH = 'DOCKER_CERT_PATH';
	public inline static var DOCKER_CA = 'DOCKER_CA';
	public inline static var DOCKER_CERT = 'DOCKER_CERT';
	public inline static var DOCKER_KEY = 'DOCKER_KEY';

	/**
	 * If we're running on the host (not in a container) then
	 * the address to the docker machine is getDockerHost()
	 * otherwise it's localhost.
	 * @return [description]
	 */
	public static function getLocalDockerHost() :Host
	{
		return getContainerAddress('localhost');
	}

	public static function getContainerAddress(linkName :String) :Host
	{
		if (isInsideContainer()) {
			return linkName;
		} else {
			return getDockerHost();
		}
	}

	public static function getLocalRegistryHost() :Host
	{
		if (isInsideContainer()) {
			return 'registry:5000';
		} else {
			return getDockerHost() + ':5001;';
		}
	}

	/**
	 * Assuming this process is in a container, get the host IP address.
	 * This might not be available, usually you have to pass in --net='host'
	 * @return The ip address of the host system.
	 */
	public static function getDockerHost() :String
	{
		if (Reflect.field(js.Node.process.env, DOCKER_HOST) != null) {
			var host :String = Reflect.field(js.Node.process.env, DOCKER_HOST);//Looks like: tcp://192.168.59.103:2376
			host = host.replace('tcp://', '');
			return host.split(':')[0];
		} else if (isDockerMachineAvailable()) {
			var stdout :String = js.node.ChildProcess.execSync("docker-machine ip default", {stdio:['ignore','pipe','ignore']});
			return Std.string(stdout).trim();
		} else {
			//Nothing defined, last guess: are we in a container?
			try {
				//https://github.com/docker/docker/issues/1143
				// var stdout :String = js.node.ChildProcess.execSync("/sbin/ifconfig docker0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'", {stdio:['ignore','pipe','ignore']});
				var stdout :String = js.node.ChildProcess.execSync("netstat -nr | grep '^0\\.0\\.0\\.0' | awk '{print $2}'", {stdio:['ignore','pipe','ignore']});
				return Std.string(stdout).trim();
			} catch (ignored :Dynamic) {
				throw 'Exhausted all methods to determine the docker server host. "$DOCKER_HOST" is not defined in the env vars, "docker0" is not defined in /etc/hosts, and "docker-machine" is either not installed or a machine called "default" is not running (where a redis container might be running).';
				return null;
			}
		}
	}

	public static function getDocker() :Docker
	{
		return new Docker(getDockerConfig());
	}

	public static function isDockerMachineAvailable() :Bool
	{
		try {
			var stdout :String = js.node.ChildProcess.execSync("which docker-machine", {stdio:['ignore','pipe','ignore']});
			return Std.string(stdout).trim().startsWith('/usr/local');
		} catch (ignored :Dynamic) {
			return false;
		}
	}

	public static function getDockerConfig() :ConstructorOpts
	{
		/**
		 * There are X scenarios for connecting to a 'local' docker
		 * host:
		 * 1) This process is running (NON-containerized) on the host,
		 *    so therefore use env then fall back to querying docker-machine
		 *    directly. This means you are running directly on your laptop OS.
		 * 2) This process is running in a priviledged container. If the
		 *    docker server host is not passed as an env var, then we have to
		 *    query directly for the IP address by looking at the network stack.
		 *    Also if the docker server socket isn't passed in then we need
		 *    all the credentials passed in as env vars.
		 */
		if (isLocalDockerHost()) {//This only exists if running on a linux host or passed via a volume
			return getLocalDockerOpts();
		}

		var certPath = Reflect.field(Node.process.env, DOCKER_CERT_PATH);
		if (certPath != null) {
			//This process is running with a docker-machine process available
			return {
				protocol: 'https',
				host: getDockerHost(),
				port: getDockerPort(),
				ca: Fs.readFileSync(Path.join(certPath, 'ca.pem'), {encoding:'utf8'}),
				cert: Fs.readFileSync(Path.join(certPath, 'cert.pem'), {encoding:'utf8'}),
				key: Fs.readFileSync(Path.join(certPath, 'key.pem'), {encoding:'utf8'})
			};
		} else {
			return getDockerMachineConfig();
		}
	}

	public static function getDockerMachineConfig(?name :String = "default") :ConstructorOpts
	{
#if debug
		Assert.that(isDockerMachineAvailable());
#end
		var stdout :String = js.node.ChildProcess.execSync('docker-machine config $name', {});
		var output = Std.string(stdout);
		var tokens = output.split(' -');

		function getConfigValue(key) {
			return tokens.find(function(s) return s.indexOf(key) > -1);
		}

		function getPath(key :String) {
			var input = getConfigValue(key);
			var tokens = input.split('=');
			return tokens[1].replace('"', '').trim();
		}

		var hostTokens = getConfigValue('H').split('://');
		var address = hostTokens[hostTokens.length - 1];
		hostTokens = address.split(":");

		var result :ConstructorOpts = {
			protocol: 'https',
			ca: Fs.readFileSync(getPath('tlscacert'), {encoding:'utf8'}),
			cert: Fs.readFileSync(getPath('tlscert'), {encoding:'utf8'}),
			key: Fs.readFileSync(getPath('tlskey'), {encoding:'utf8'}),
			host: hostTokens[0],
			port: Std.parseInt(hostTokens[1])
		};
		return result;
	}

	static function getDockerPort() :Int
	{
		var host :String = Reflect.field(js.Node.process.env, 'DOCKER_HOST');//Looks like: tcp://192.168.59.103:2376
		if (host != null) {
			host = host.replace('tcp://', '');
			return Std.parseInt(host.split(':')[1]);
		} else if (isDockerMachineAvailable()) {
			return getDockerMachineConfig().port;
		} else {
			//Use default
			return 2376;
		}
	}

	public static function isLocalDockerHost() :Bool
	{
		try {
			Fs.statSync('/var/run/docker.sock');
			//No error thrown means it exists
			return true;
		} catch(err :Dynamic) {
			//No local file, ignore this error
			return false;
		}
	}

	public static function isInsideContainer() :Bool
	{
		//http://stackoverflow.com/questions/23513045/how-to-check-if-a-process-is-running-inside-docker-container
		try {
			var stdout :String = js.node.ChildProcess.execSync('cat /proc/1/cgroup', {stdio:['ignore','pipe','ignore']});
			var output = Std.string(stdout);
			return output.indexOf('/docker') > -1;
		} catch (ignored :Dynamic) {
			return false;
		}
	}

	static function getLocalDockerOpts() :ConstructorOpts
	{
		return {socketPath:'/var/run/docker.sock'};
	}
}
