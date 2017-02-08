package ccc.compute.server;

import js.Node;
import js.node.Fs;
import js.node.Path;
import js.npm.docker.Docker;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

import t9.abstracts.net.*;
import util.DockerTools.*;

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

	public static function getDockerConfig() :DockerConnectionOpts
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

	static function getLocalDockerOpts() :DockerConnectionOpts
	{
		return {socketPath:'/var/run/docker.sock'};
	}

	inline static var DOCKER_HOST = 'DOCKER_HOST'; //Looks like: tcp://192.168.59.103:2376
}
