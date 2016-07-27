package ccc.compute.workers;

import util.DockerTools;

import haxe.Json;
import haxe.Resource;

import js.Node;
import js.node.Path;
import js.node.Fs;

import js.npm.docker.Docker;
import js.npm.fsextended.FsExtended;
import js.npm.FsPromises;
import js.npm.RedisClient;
import js.npm.ssh2.Ssh;
import js.npm.vagrant.Vagrant;

import promhx.Promise;
import promhx.deferred.DeferredPromise;
import promhx.RedisPromises;
import promhx.DockerPromises;

import ccc.compute.ComputeTools;
import ccc.compute.InstancePool;
import ccc.compute.workers.VagrantTools;
import ccc.compute.workers.WorkerProviderPkgCloud;

import util.SshTools;
import util.Predicates;
import t9.abstracts.net.*;
import t9.abstracts.time.*;
import util.streams.StdStreams;
import util.TarTools;

using StringTools;
using util.RedisTools;
using ccc.compute.ComputeTools;
using ccc.compute.workers.WorkerProviderTools;
using ccc.compute.workers.WorkerTools;
using promhx.PromiseTools;
using Lambda;
using util.MapTools;

class WorkerProviderTools
{
	public static function getPublicHostName(config :ServiceConfigurationWorkerProvider) :Promise<HostName>
	{
		return switch(config.type) {
			case pkgcloud:
				return WorkerProviderPkgCloud.getPublicHostName(config);
			case boot2docker:
				return Promise.promise(new HostName('localhost'));
			default:
				throw 'Not yet implemented';
		}
	}

	public static function getPrivateHostName(config :ServiceConfigurationWorkerProvider) :Promise<HostName>
	{
		return switch(config.type) {
			case pkgcloud:
				return WorkerProviderPkgCloud.getPrivateHostName(config);
			case boot2docker:
				return Promise.promise(new HostName('localhost'));
			default:
				throw 'Not yet implemented';
		}
	}

	public static function getProvider(config :ServiceConfigurationWorkerProvider) :WorkerProvider
	{
		var className = 'ccc.compute.workers.WorkerProvider' + config.type;
		var cls = Type.resolveClass(className);
		Assert.notNull(cls);
		var provider :WorkerProvider = Type.createInstance(cls, [config]);
		return provider;
	}

	public static function registerProvider(provider :WorkerProvider, priority :WorkerPoolPriority, maxWorkers :WorkerCount, minWorkers :WorkerCount, billingIncrements :Minutes) :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				return InstancePool.registerComputePool(provider.redis, provider.id, priority, maxWorkers, minWorkers, billingIncrements);
			})
			.thenTrue();
	}

	public static function getWorkerParameters(opts :DockerConnectionOpts) :Promise<WorkerParameters>
	{
		return DockerPromises.info(new Docker(opts))
			.then(function(dockerinfo :DockerInfo) {
				var parameters :WorkerParameters = {
					cpus: dockerinfo.NCPU,
					memory: dockerinfo.MemTotal
				};
				return parameters;
			});
	}

	public static function pollInstanceUntilSshReady(sshOptions :ConnectOptions) :Promise<Bool>
	{
		var retryAttempts = 240;
		var doublingTimeInterval = 2000;
		return SshTools.getSsh(sshOptions, retryAttempts, doublingTimeInterval, promhx.RetryPromise.PollType.regular, 'pollInstanceUntilSshReady')
			.then(function(ssh) {
				ssh.end();
				return true;
			});
	}

	/**
	 * https://coreos.com/os/docs/latest/customizing-docker.html
	 * @param  worker :MachineDefinition [description]
	 * @return        [description]
	 */
	public static function setupCoreOS(sshOptions :ConnectOptions, ?log :AbstractLogger)
	{
		log = Logger.ensureLog(log, {f:setupCoreOS, host:sshOptions.host});

		log.debug({state:'start'});
		var retryAttempts = 12;
		var doublingTimeInterval = 200;
		log.debug({state:'get_ssh'});
		return SshTools.getSsh(sshOptions, retryAttempts, doublingTimeInterval)
			.pipe(function(ssh) {
				ssh.end();
				log.debug({state:'get_sftp'});
				log.debug({state:'writing_file'});
				var dockerSocketFile = 'etc/vagrant/coreos/docker-tcp.socket';
				Assert.notNull(Resource.getString(dockerSocketFile), 'Missing resource $dockerSocketFile');
				return SshTools.writeFileString(sshOptions, '/tmp/docker-tcp.socket', Resource.getString(dockerSocketFile))
					.pipe(function(_) {
						log.debug({state:'executing_custom_commands'});
						return SshTools.executeCommands(sshOptions, [
							//https://github.com/coreos/coreos-vagrant/issues/235
							//Set up the insecure registry config
							'sudo cp /usr/lib/systemd/system/docker.service /etc/systemd/system/',
							'sudo sed -e "/^ExecStart/ s|$$| --insecure-registry=0.0.0.0/0 |" -i /etc/systemd/system/docker.service',
							//This sets up the remote API
							'sudo cp /tmp/docker-tcp.socket /etc/systemd/system/docker-tcp.socket',
							'sudo systemctl enable docker-tcp.socket',
							'sudo systemctl stop -q docker', //Shuttup with your noisy output.
							//Insecure registry load
							'sudo systemctl daemon-reload',
							//Start the socket and restart docker
							'sudo systemctl start docker-tcp.socket',
							'sudo systemctl start docker',
							'sudo mkdir -p "$WORKER_JOB_DATA_DIRECTORY_HOST_MOUNT"',
							'sudo chmod 777 "$WORKER_JOB_DATA_DIRECTORY_HOST_MOUNT"'
						]);
					})
					.pipe(function(_) {
						//Validate by checking the last command
						return SshTools.execute(sshOptions, 'ls "$WORKER_JOB_DATA_DIRECTORY_HOST_MOUNT"', 3, 100)
							.then(function(execResult) {
								if (execResult.code != 0) {
									throw 'Failed to set up CoreOS worker';
								}
								return true;
							});
					})
					.thenTrue();
			});
	}
}