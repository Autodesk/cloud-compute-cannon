package ccc.compute.workers;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;

import js.npm.PkgCloud;
import js.npm.docker.Docker;
import js.npm.ssh2.Ssh;
import js.npm.RedisClient;

import promhx.Promise;
import promhx.StreamPromises;
import promhx.RequestPromises;
import promhx.RetryPromise;

import ccc.compute.workers.WorkerProvider;
import ccc.compute.ComputeTools;
import ccc.compute.InstancePool;
import ccc.compute.ConnectionToolsDocker;
import ccc.storage.ServiceStorage;
import ccc.storage.StorageDefinition;
import ccc.storage.StorageSourceType;
import ccc.storage.StorageTools;
import ccc.storage.ServiceStorageLocalFileSystem;

import util.SshTools;
import t9.abstracts.net.*;

using StringTools;
using util.RedisTools;
using ccc.compute.ComputeTools;
using promhx.PromiseTools;

/**
 * This doesn't actually do any 'workers', it just provides
 * access to the local boot2docker/docker system.
 */
class WorkerProviderBoot2Docker extends WorkerProviderBase
{
	public static function setHostWorkerDirectoryMount()
	{
		//The mount point for worker job data (inputs/outputs mounted to the job container)
		//depends on if the server is running in a docker container or not.
		if (ConnectionToolsDocker.isInsideContainer()) {
			if (Node.process.env['HOST_PWD'] == null || Node.process.env['HOST_PWD'] == '') {
				Log.critical('WorkerProviderBoot2Docker needs HOST_PWD defined if running inside a container.');
				js.Node.process.exit(-1);
			}
			Constants.LOCAL_WORKER_HOST_MOUNT_PREFIX = Path.join(Node.process.env['HOST_PWD'], 'data');
		} else {
			Constants.LOCAL_WORKER_HOST_MOUNT_PREFIX = Path.join(Node.process.cwd(), 'data');
		}
	}

	public static function getService(redis :js.npm.RedisClient) :WorkerProvider
	{
		var worker = getLocalDockerWorker();
		var provider = new WorkerProviderBoot2Docker();
		provider._redis = redis;
		provider.postInjection();
		return provider;
	}

	public static function getLocalDockerWorker()
	{
		var dockerHost = ConnectionToolsDocker.getDockerHost();
		// var ssh = getSshConfig();
		var boot2docker :WorkerDefinition = {
			id: ID,
			hostPublic: dockerHost,
			hostPrivate: dockerHost,
			docker: ConnectionToolsDocker.getDockerConfig(),
			ssh: null
		};
		if (boot2docker.ssh == null) {
			Reflect.deleteField(boot2docker, 'ssh');
		}
		return boot2docker;
	}

	/**
	 * This method should be obsolete since file access on local docker
	 * providers are now using direct file access with mounted local volumes.
	 * @param  ?throwIfMissing :Bool         [description]
	 * @return                 [description]
	 */
	// @deprecated
	// public static function OBSOLETEisSftpConfigInLocalDockerMachine(?throwIfMissing :Bool = true) :Promise<Bool>
	// {
	// 	var config :StorageDefinition = {
	// 		type: StorageSourceType.Sftp,
	// 		rootPath: '/',
	// 		sshConfig: getSshConfig()
	// 	};
	// 	var storage = StorageTools.getStorage(config);
	// 	return storage.readFile(LOCAL_DOCKER_SSH_CONFIG_PATH)
	// 		.pipe(StreamPromises.streamToString)
	// 		.then(function(s) {
	// 			return s.indexOf(DOCKER_SSH_CONFIG_SFTP_ADDITION) > -1;
	// 		})
	// 		.errorPipe(function(err) {
	// 			Log.error(err);
	// 			return Promise.promise(false);
	// 		});
	// }

	public static function getLocalDocker() :Docker
	{
		return new Docker(getLocalDockerWorker().docker);
	}

	// public static function getSshConfig() :js.npm.ssh2.Ssh.ConnectOptions
	// {
	// 	return {
	// 		host: ConnectionToolsDocker.getDockerHost(),
	// 		port: 22,
	// 		username: 'docker',
	// 		password: 'tcuser'
	// 	};
	// }

	inline static var ID = 'dockermachinedefault';

	var _currentWorkers = Set.createInt();
	@inject public var _injector :minject.Injector;
	#if debug public #end
	var _localJobData :String;

	public function new(?config :ServiceConfigurationWorkerProvider)
	{
		super(config);
		this.id = ID;
		if (_config == null) {
			_config = {
				minWorkers: 0,
				maxWorkers: 2,
				priority: 1,
				billingIncrement: 0
			};
		}

		var hostName = ConnectionToolsDocker.getDockerHost();
		Constants.REGISTRY = new Host(hostName, new Port(REGISTRY_DEFAULT_PORT));
		setHostWorkerDirectoryMount();
		_localJobData = WORKER_JOB_DATA_DIRECTORY_WITHIN_CONTAINER;
		if (!ConnectionToolsDocker.isInsideContainer()) {
			//If inside the container, use the mounted directory for file system access.
			_localJobData = Constants.LOCAL_WORKER_HOST_MOUNT_PREFIX + WORKER_JOB_DATA_DIRECTORY_WITHIN_CONTAINER;
		}
	}

	@post
	override public function postInjection() :Promise<Bool>
	{
		log.debug({f:'postInjection'});
		//Something a bit hack-ish:
		//If the stack is using the local docker as the worker provider,
		//then you need to mount a special ServiceStorage to avoid the
		//need to SFTP into the local docker-machine (this is a pain setting up.)
		//It does introduce some awkwardness regarding figuring out the correct
		//ServiceStorage for the 'worker'.
		var workerStorage = ServiceStorageLocalFileSystem.getService(_localJobData);
		_injector.map(ServiceStorage, BOOT2DOCKER_PROVIDER_STORAGE_PATH).toValue(workerStorage);
		return super.postInjection();
	}

	override public function removeWorker(id :MachineId)
	{
		return Promise.promise(true);
	}

	override public function createWorker()
	{
		var machineDef = getLocalDockerWorker();
		return WorkerProviderTools.getWorkerParameters(machineDef.docker)
			.pipe(function(params) {
				return InstancePool.addInstance(_redis, id, machineDef, params);
			})
			.then(function(_) {
				return machineDef;
			});
	}

	function updateWorkerCount() :Promise<Bool>
	{
		if (_targetWorkerCount.toInt() > 0) {
			return createWorker()
				.thenTrue();
		} else {
			//TODO: remove the worker from the DB?
			return Promise.promise(true);
		}
	}
}