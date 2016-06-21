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
		return new HostName('localhost');
	}

	public static function getDocker() :Docker
	{
		return new Docker(getDockerConfig());
	}

	public static function getDockerConfig() :ConstructorOpts
	{
		return getLocalDockerOpts();
	}

	static function getDockerPort() :Int
	{
		return 2376;
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
