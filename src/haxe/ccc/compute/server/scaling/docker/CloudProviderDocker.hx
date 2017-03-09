package ccc.compute.server.scaling.docker;

class CloudProviderDocker
	implements ICloudProvider
{
	@inject public var log :AbstractLogger;

	var _docker :Docker;
	var _containerId :MachineId;
	var _hostPublic :String;
	var _hostPrivate :String;

	public function new() {}

	@post public function postInject()
	{
		_containerId = DockerTools.getContainerId();
		log = log.child({containerId:_containerId, c:Type.getClassName(Type.getClass(this)).split('.').pop()});
		_docker = new Docker({socketPath:'/var/run/docker.sock'});
	}

	public function getId() :Promise<MachineId>
	{
		return Promise.promise(_containerId);
	}

	public function getHostPublic() :Promise<String>
	{
		return Promise.promise(null);
	}

	public function getHostPrivate() :Promise<String>
	{
		if (_hostPrivate != null) {
			return Promise.promise(_hostPrivate);
		} else {
			var container = _docker.getContainer(_containerId);
			return DockerPromises.inspect(container)
				.then(function(data) {
					var Networks = data.NetworkSettings.Networks;
					var network1 :{IPAddress:String} = Reflect.field(Networks, Reflect.fields(Networks).pop());
					var gateway = network1.IPAddress;//network1.Gateway;
					_hostPrivate = gateway;
					return gateway;
				});
		}
	}

	/**
	 * The local provider cannot actually check the local disk,
	 * it is unknown where it should be mounted.
	 * @param  ?threshold :Float        [description]
	 * @return            [description]
	 */
	public function getDiskUsage() :Promise<Float>
	{
		return Promise.promise(0.1);
	}

	/**
	 * For local docker, containers can shut down immediately.
	 * @return [description]
	 */
	public function getBestShutdownTime() :Promise<Float>
	{
		return Promise.promise(Date.now().getTime() - 1000);
	}

	public function shutdownThisInstance() :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				var container = _docker.getContainer(_containerId);
				return DockerPromises.killContainer(container)
					.errorPipe(function(err) {
						log.info({error:err, log:'Error shutting down container'});
						return Promise.promise(true);
					});
			});
	}

	public function createWorker() :Promise<Bool>
	{
		var promise = new DeferredPromise();
		var container = _docker.getContainer(_containerId);

		container.inspect(function(err, data) {
			if (err != null) {
				promise.boundPromise.reject({error:err, m:'createWorker container.inspect'});
				return;
			} else {
				// log.info({data:data, m:'createWorker container.inspect'});

				var create_options  = data.Config;
				create_options.ExposedPorts = null;//Don't expose, otherwise we'll conflict
				create_options.AttachStdin = false;
				create_options.AttachStdout = false;
				create_options.AttachStderr = false;
				create_options.HostConfig = data.HostConfig;
				create_options.HostConfig.Links = ['redis', 'fluentd'];
				create_options.HostConfig.PortBindings = null;
				create_options.Env = create_options.Env.filter(function(e) return !e.startsWith(ENV_SCALE_DOWN_CONTROL)).array();
				//This means the worker can shut itself down
				create_options.Env.push('$ENV_SCALE_DOWN_CONTROL=internal');
				//This means that a worker cannot create new workers
				create_options.Env.push('$ENV_SCALE_UP_CONTROL=external');

				var start_options = {};
				_docker.createContainer(create_options, function(err, container) {

					if (err != null) {
						log.error({error:err, m:'createWorker createContainer'});
						promise.boundPromise.reject({error:err, m:'createWorker createContainer', containerId:_containerId});
						return;
					}
					container.start(function(err, data) {
						if (err != null) {
							log.error({error:err, m:'createWorker container.start'});
							promise.boundPromise.reject({error:err, m:'createWorker container.start', containerId:_containerId});
							return;
						}
						log.info('Successful start of scaled up docker container ' + container.id + " !");
						promise.resolve(true);
					});
				});
			}
		});

		return promise.boundPromise;
	}

	public function terminate(id :MachineId) :Promise<Bool>
	{
		var container = _docker.getContainer(id);
		return DockerPromises.killContainer(container)
			.errorPipe(function(err) {
				log.warn({error:err, log:'Attempting to kill worker=$id'});
				return Promise.promise(true);
			});
	}

	public function dispose() :Promise<Bool>
	{
		return Promise.promise(true);
	}
}