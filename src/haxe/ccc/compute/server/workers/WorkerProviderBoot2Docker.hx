package ccc.compute.server.workers;

import js.npm.PkgCloud;
import js.npm.docker.Docker;
import js.npm.ssh2.Ssh;
import js.npm.RedisClient;

import ccc.storage.*;

import util.SshTools;
import t9.abstracts.net.*;

using util.RedisTools;

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
		if (util.DockerTools.isInsideContainer()) {
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
		var boot2docker :WorkerDefinition = {
			id: cast ServiceWorkerProviderType.boot2docker,
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

	public static function getLocalDocker() :Docker
	{
		return new Docker(getLocalDockerWorker().docker);
	}

	var _currentWorkers = Set.createInt();
	@inject public var _injector :minject.Injector;
	#if debug public #end
	var _localJobData :String;

	public function new(?config :ServiceConfigurationWorkerProvider)
	{
		super(config);
		this.id = ServiceWorkerProviderType.boot2docker;
		if (_config == null) {
			_config = {
				minWorkers: 0,
				maxWorkers: 2,
				priority: 1,
				billingIncrement: 0
			};
		}

		var hostName = ConnectionToolsDocker.getDockerHost();
		setHostWorkerDirectoryMount();
		_localJobData = WORKER_JOB_DATA_DIRECTORY_WITHIN_CONTAINER;
		if (!util.DockerTools.isInsideContainer()) {
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
		_injector.map(ServiceStorage, SERVER_MOUNTED_CONFIG_FILE_NAME).toValue(workerStorage);
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