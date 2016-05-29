package ccc.compute.workers;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;

import js.npm.PkgCloud;
import js.npm.Docker;
import js.npm.Ssh;
import js.npm.RedisClient;

import promhx.Promise;
import promhx.StreamPromises;
import promhx.RequestPromises;
import promhx.RetryPromise;

import ccc.compute.workers.WorkerProvider;
import ccc.compute.ComputeTools;
import ccc.compute.InstancePool;
import ccc.compute.Definitions;
import ccc.compute.Definitions.Constants.*;
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
	public static function getService(redis :js.npm.RedisClient) :WorkerProvider
	{
		var worker = getLocalDockerWorker();
		var provider = new WorkerProviderBoot2Docker();
		provider._redis = redis;
		provider.postInjection();
		return provider;
	}

	// public static function getWorkerStorage() :ServiceStorage
	// {
	// 	var workerDef = getLocalDockerWorker();
	// 	var workerStorageConfig :StorageDefinition = {
	// 		type: StorageSourceType.Sftp,
	// 		rootPath: DIRECTORY_WORKER_BASE,
	// 		sshConfig: workerDef.ssh
	// 	};
	// 	return StorageTools.getStorage(workerStorageConfig);
	// }

	public static function getLocalDockerWorker()
	{
		var ssh = getSshConfig();
		var boot2docker :WorkerDefinition = {
			id: 'dockermachinedefault',
			hostPublic: new HostName(ssh.host),
			hostPrivate: new HostName(ssh.host),
			docker: ConnectionToolsDocker.getDockerConfig(),
			ssh: ssh
		};
		return boot2docker;
	}

	public static function isSftpConfigInLocalDockerMachine(?throwIfMissing :Bool = true) :Promise<Bool>
	{
		var config :StorageDefinition = {
			type: StorageSourceType.Sftp,
			rootPath: '/',
			sshConfig: getSshConfig()
		};
		var storage = StorageTools.getStorage(config);
		return storage.readFile(LOCAL_DOCKER_SSH_CONFIG_PATH)
			.pipe(StreamPromises.streamToString)
			.then(function(s) {
				return s.indexOf(DOCKER_SSH_CONFIG_SFTP_ADDITION) > -1;
			})
			.errorPipe(function(err) {
				Log.error(err);
				return Promise.promise(false);
			});
	}

	public static function getLocalDocker() :Docker
	{
		return new Docker(getLocalDockerWorker().docker);
	}

	public static function getSshConfig() :js.npm.Ssh.ConnectOptions
	{
		return {
			host: ConnectionToolsDocker.getDockerHost(),
			port: 22,
			username: 'docker',
			password: 'tcuser'
		};
	}

	inline static var ID = 'dockermachinedefault';

	var _currentWorkers = Set.createInt();
	@inject public var _injector :minject.Injector;
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
	}

	@post
	override public function postInjection() :Promise<Bool>
	{
		log.debug({f:'postInjection'});
		//The mount point for worker job data (inputs/outputs mounted to the job container)
		//depends on if the server is running in a docker container or not.
		if (ConnectionToolsDocker.isInsideContainer()) {
			Constants.JOB_DATA_DIRECTORY_HOST_MOUNT = Path.join(Node.process.env['HOST_PWD'], 'data/$DIRECTORY_NAME_WORKER_OUTPUT');
			//If inside the container, use the mounted directory for file system access.
			_localJobData = JOB_DATA_DIRECTORY_WITHIN_CONTAINER;
		} else {
			var baseWorkerDataPath = Path.join(Node.process.cwd(), 'data/$DIRECTORY_NAME_WORKER_OUTPUT');
			Constants.JOB_DATA_DIRECTORY_HOST_MOUNT = baseWorkerDataPath;
			//If outside the container, use the local directory
			_localJobData = baseWorkerDataPath;
		}
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