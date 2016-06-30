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

	public static function getContainerAddress(linkName :String) :HostName
	{
		if (isInsideContainer()) {
			return new HostName(linkName);
		} else {
			return getDockerHost();
		}
	}

	public static function getLocalRegistryHost() :Host
	{
		if (isInsideContainer()) {
			return 'registry:$REGISTRY_DEFAULT_PORT';
		} else {
			return new Host(getDockerHost(), new Port(REGISTRY_DEFAULT_PORT));
		}
	}

	/**
	 * Assuming this process is in a container, get the host IP address.
	 * This might not be available, usually you have to pass in --net='host'
	 * @return The ip address of the host system.
	 */
	public static function getDockerHost() :HostName
	{
		if (Reflect.field(js.Node.process.env, DOCKER_HOST) != null) {
			var host :String = Reflect.field(js.Node.process.env, DOCKER_HOST);//Looks like: tcp://192.168.59.103:2376
			host = host.replace('tcp://', '');
			return new HostName(host.split(':')[0]);
		} else if (isDefaultDockerMachine()) {
			var stdout :String = js.node.ChildProcess.execSync("docker-machine ip default", {stdio:['ignore','pipe','ignore']});
			return new HostName(Std.string(stdout).trim());
		} else {
			//Nothing defined, last guess: are we in a container?
			try {
				//https://github.com/docker/docker/issues/1143
				var stdout :String = js.node.ChildProcess.execSync("netstat -nr | grep '^0\\.0\\.0\\.0' | awk '{print $2}'", {stdio:['ignore','pipe','ignore']});
				if (stdout == null || stdout.trim().length == 0) {
					return new HostName('localhost');
				} else {
					return new HostName(Std.string(stdout).trim());
				}
			} catch (ignored :Dynamic) {
				//Localhost
				return new HostName('localhost');
			}
		}
	}

	static function isDefaultDockerMachine() :Bool
	{
		if (isDockerMachineAvailable()) {

			try {
				var stdout :String = js.node.ChildProcess.execSync("docker-machine ip default", {stdio:['ignore','pipe','ignore']});
				return true;
			} catch(err :Dynamic) {
				return false;
			}
		} else {
			return false;
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
			return true;
		} catch (ignored :Dynamic) {
			return false;
		}
	}

	public static function getDockerConfig() :ConstructorOpts
	{
		return getLocalDockerOpts();
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
