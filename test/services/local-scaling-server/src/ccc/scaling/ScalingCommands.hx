package ccc.scaling;

import ccc.lambda.*;

@:build(t9.redis.RedisObject.build())
class ScalingCommands
{
	static var PREFIX :String = '${CCC_PREFIX}scalingtest${SEP}';
	static var REDIS_CHANNEL_SCALING_STATUS :String = '${PREFIX}channel${SEP}status';
	static var REDIS_KEY_SCALING_STATUS :String = '${PREFIX}status';
	static var REDIS_KEY_WORKER_DOCKER_CONFIG :String = '${PREFIX}worker_docker_config';

	static var DOCKER_LABEL_CCC_TYPE = 'ccc.type';
	static var DOCKER_LABEL_CCC_TYPE_TYPE_WORKER = 'worker';
	static var DOCKER_LABEL_CCC_TEST_WORKER = 'ccc.test.worker';

	static var docker :Docker;
	static var lambdaScaling :LambdaScaling;

	public static function inject(injector :Injector)
	{
		docker = injector.getValue(Docker);

		return Promise.promise(true)
			.pipe(function(_) {
				var p = init(injector.getValue(RedisClient));
				return p;
			})
			.pipe(function(_) {
				return getCccContainerInfo();
			})
			.then(function(_) {
				lambdaScaling = new LambdaScalingLocal();
				injector.map(LambdaScaling).toValue(lambdaScaling);
				injector.injectInto(lambdaScaling);
			})
			.thenTrue();
	}

	public static function getStatusStream() :Stream<MinMaxDesired>
	{
		var StatusStream :Stream<MinMaxDesired> =
			RedisTools.createStreamCustom(
				REDIS_CLIENT,
				REDIS_CHANNEL_SCALING_STATUS,
				function(statusString :String) {
					if (statusString != null) {
						traceCyan('statusString=${statusString}');
						return Promise.promise(Json.parse(statusString));
					} else {
						return Promise.promise(null);
					}
				});
		StatusStream.catchError(function(err) {
			Log.error({error:err, message: 'Failure on '});
		});
		return StatusStream;
	}

	public static function getCccContainerInfo() :Promise<ContainerData>
	{
		return DockerPromises.listContainers(docker)
			.then(function(containers) {
				for (container in containers) {
					if (Reflect.hasField(container.Labels, DOCKER_LABEL_CCC_TYPE) && Reflect.field(container.Labels, 'ccc.origin') == 'docker-compose') {
						return container;
					}
				}
				return null;
			})
			.pipe(function(containerData) {
				if (containerData != null) {
					return RedisPromises.set(REDIS_CLIENT, REDIS_KEY_WORKER_DOCKER_CONFIG, Json.stringify(containerData))
						.then(function(_) {
							return containerData;
						});
				} else {
					return RedisPromises.get(REDIS_CLIENT, REDIS_KEY_WORKER_DOCKER_CONFIG)
						.then(Json.parse);
				}
			});
	}

	public static function getTestWorkers() :Promise<Array<ContainerData>>
	{
		return DockerPromises.listContainers(docker)
			.then(function(containers) {
				return containers.filter(function(c) {
					return Reflect.hasField(c.Labels, DOCKER_LABEL_CCC_TYPE)
						&& Reflect.field(c.Labels, 'ccc.test.worker') == 'true';
				});
			});
	}

	public static function getAllDockerWorkerIds() :Promise<Array<MachineId>>
	{
		return DockerPromises.listContainers(docker)
			.then(function(containers) {
				return containers.filter(function(c) {
					return Reflect.field(c.Labels, DOCKER_LABEL_CCC_TYPE) == DOCKER_LABEL_CCC_TYPE_TYPE_WORKER;
				})
				.map(function(c) return c.Id);
			});
	}

	public static function createWorker(?workerOpts :{disableWorker :Bool, disableServer :Bool}) :Promise<DockerContainerId>
	{
		Log.info({event:'CreateWorker'});
		return getCccContainerInfo()
			.pipe(function(containerInfo) {
				var Labels :DynamicAccess<String> = {};
				Labels.set(DOCKER_LABEL_CCC_TYPE, DOCKER_LABEL_CCC_TYPE_TYPE_WORKER);
				Labels.set(DOCKER_LABEL_CCC_TEST_WORKER, "true");

				var opts :CreateContainerOptions = {
					name: 'LOCAL_WORKER' + Std.int(Math.random() * 100000000),
					Image: containerInfo.Image,
					AttachStdin: false,
					AttachStdout: false,
					AttachStderr: false,
					Env: [
						'REDIS_HOST=redis',
						'FLUENT_HOST=fluentd',
						'STORAGE_HTTP_PREFIX=http://ccc.local/',
						'LOG_LEVEL=debug',
					],
					Cmd: containerInfo.Command.split(' '),
					HostConfig: {
						NetworkMode: containerInfo.HostConfig.NetworkMode,
						Binds: containerInfo.Mounts.map(function(m) {
							return m.Source + ':' + m.Destination + ':rw';
						}),
						PortBindings: {
							'9000/tcp':[]
						}
					},
					Labels: Labels,
					WorkingDir: '/app',
					ExposedPorts: {
						'9000/tcp':{}
					},
					NetworkSettings: containerInfo.NetworkSettings
				};

				if (workerOpts != null && workerOpts.disableWorker) {
					opts.Env.push('DISABLE_WORKER=true');
				}

				if (workerOpts == null || !workerOpts.disableServer) {
					//For the nginx reverse proxy
					opts.Env.push('VIRTUAL_HOST=ccc.local');
				}

				return DockerPromises.createContainer(docker, opts)
					.pipe(function(container) {
						var promise = new DeferredPromise();
						container.start(function(err, data) {
							if (err != null) {
								Log.error({error:err, m:'createWorker container.start'});
								promise.boundPromise.reject({error:err, m:'createWorker container.start', containerId:container.id});
								return;
							}
							Log.info({event:'ContainerStarted', id:container.id});
							promise.resolve(container.id);
						});
						return promise.boundPromise;
					});
			});
	}

	public static function killWorker(workerId :MachineId) :Promise<Bool>
	{
		Log.info({event:'KillWorker', id:workerId});
		var container = docker.getContainer(workerId);
		return DockerPromises.killContainer(container)
			.errorPipe(function(err) {
				Log.error({event:'KillWorkerFailed', id:workerId, err:err});
				return Promise.promise(true);
			})
			.pipe(function(_) {
				Log.info({event:'ContainerRemoving', id:workerId});
				return DockerPromises.removeContainer(container)
					.errorPipe(function(err) {
						Log.error(err);
						return Promise.promise(true);
					});
			});
	}


	public static function getState() :Promise<MinMaxDesired>
	{
		return RedisPromises.get(REDIS_CLIENT, REDIS_KEY_SCALING_STATUS)
			.then(Json.parse);
	}

	static var SNIPPET_SAVE_AND_PUBLISH_STATE = '
		redis.call("SET", "$REDIS_KEY_SCALING_STATUS", cjson.encode(state))
		redis.call("PUBLISH", "$REDIS_CHANNEL_SCALING_STATUS", cjson.encode(state))
	';
	static var SNIPPET_BOUND_DESIRED_VALUE = '
		if state.DesiredCapacity > state.MaxSize then
			state.DesiredCapacity = state.MaxSize
		end
		if state.DesiredCapacity < state.MinSize then
			state.DesiredCapacity = state.MinSize
		end
	';

	static var SCRIPT_SET_STATE = '
		local stateString = ARGV[1]
		local state = cjson.decode(stateString)
		$SNIPPET_SAVE_AND_PUBLISH_STATE
	';
	@redis({lua:'${SCRIPT_SET_STATE}'})
	static function setStateInternal(status :String) :Promise<Bool> {}
	public static function setState(status :MinMaxDesired) :Promise<Bool>
	{
		return setStateInternal(Json.stringify(status))
			.pipe(function(_) {
				return equalizeDockerToDesiredWorkers()
					.thenTrue();
			});
	}

	static var SCRIPT_SET_DESIRED = '
		local val = tonumber(ARGV[1])
		local stateString = redis.call("GET", "$REDIS_KEY_SCALING_STATUS")
		local state
		if stateString then
			state = cjson.decode(stateString)
			if val < 0 then
				val = 0
			end
			if val > state.MaxSize then
				val = state.MaxSize
			end
		else
			state = {MinSize=1,MaxSize=val,DesiredCapacity=val}
		end
		state.DesiredCapacity = val
		$SNIPPET_BOUND_DESIRED_VALUE
		$SNIPPET_SAVE_AND_PUBLISH_STATE
		return state.DesiredCapacity
	';
	@redis({lua:'${SCRIPT_SET_DESIRED}'})
	public static function setDesiredValue(v :Int) :Promise<Int> {}

	public static function setDesired(v :Int) :Promise<String>
	{
		Log.info({event:'SetDesired', value:v});
		return setDesiredValue(v)
			.pipe(function(desiredWorkerCount) {
				return equalizeDockerToDesiredWorkers();
			});
	}

	// static var equalizeDockerRunning = false;
	// static var equalizeDockerInFlight :Promise<String>;
	static var equalizeDockerPromise :Promise<String>;
	static var equalizeDockerPromiseNext :Promise<String>;
	static function equalizeDockerToDesiredWorkers() :Promise<String>
	{
		if (equalizeDockerPromise == null) {
			equalizeDockerPromise = equalizeDockerToDesiredWorkersInternal()
				.then(function(result) {
					equalizeDockerPromise = null;
					return result;
				});
			return equalizeDockerPromise;
		} else {
			if (equalizeDockerPromiseNext != null) {
				return equalizeDockerPromiseNext;
			} else {
				equalizeDockerPromiseNext = equalizeDockerPromise
					.pipe(function(result) {
						var p = equalizeDockerToDesiredWorkersInternal();
						equalizeDockerPromise = p;
						equalizeDockerPromiseNext = null;
						return p;
					});
				return equalizeDockerPromiseNext;
			}
		}
	}

	public static function equalizeDockerToDesiredWorkersInternal() :Promise<String>
	{
		Log.debug({event:'Equalize'});
		return Promise.promise(true)
			.pipe(function(_) {
				return ScalingCommands.getAllDockerWorkerIds();
			})
			.pipe(function(workerIds) {
				Log.debug({event:'Equalize', workerIds:workerIds});
				return getState()
					.pipe(function(minmax) {
						Log.debug({event:'Equalize', minmax:minmax});
						var DesiredCapacity = minmax.DesiredCapacity;
						if (workerIds.length == DesiredCapacity) {
							Log.debug({event:'Equalize', result:'NoChange'});
							return Promise.promise('NO CHANGE');
						} else if (workerIds.length > DesiredCapacity) {
								var workersToRemove = workerIds.length - DesiredCapacity;
								Log.debug({event:'Equalize', workersToRemove:'workersToRemove'});
								if (workersToRemove > 0) {
									return lambdaScaling.removeIdleWorkers(workersToRemove)
										.then(function(workerIdsRemoved) {
											Log.info({event:'Equalize', workerIdsRemoved:'workerIdsRemoved'});
											return 'Workers removed: ${workerIdsRemoved}';
										})
										.thenWait(2000);
								} else {
									return Promise.promise('No need to actually remove workers');
								}
						} else {
							var workersToAdd = DesiredCapacity - workerIds.length;
							Log.info({event:'Equalize', workersToAdd:'workersToAdd'});
							return Promise.whenAll([for (i in 0...workersToAdd) i].map(function(_) {
								return ScalingCommands.createWorker().thenTrue();
							}))
							.thenWait(2000)
							.then(function(_) return 'Created $workersToAdd workers');
						}
					});
			})
			.errorPipe(function(err) {
				traceRed(err);
				return Promise.promise('Got err=$err');
			});
	}

	public static function killAllWorkersAndJobs(docker :Docker) :Promise<Bool>
	{
		Log.debug({event:'KillAllWorkersAndJobs'});
		return Promise.promise(true)
			.pipe(function(_) {
				return JobStateTools.cancelAllJobs();
			})
			.thenWait(600)
			.pipe(function(_) {
				return ScalingCommands.getAllDockerWorkerIds()
					.pipe(function(workerIds) {
						Log.debug({event:'KillAllWorkersAndJobs', workerIds:workerIds});
						return Promise.whenAll(workerIds.map(function(id) {
							var container = docker.getContainer(id);
							Log.debug({event:'KillAllWorkersAndJobs', killingContainer:id});
							return DockerPromises.killContainer(container)
								.then(function(_) {
									Log.debug({event:'KillAllWorkersAndJobs', killed:id});
									return true;
								})
								.errorPipe(function(err) {
									Log.error({event:'KillAllWorkersAndJobs', error:err, container:id});
									return Promise.promise(true);
								});
						}));
					});
			})
			.pipe(function(_) {
				// traceCyan('Ensure a single worker');
				Log.debug({event:'KillAllWorkersAndJobs Set zero workers'});
				return ScalingCommands.setState({
					MinSize: 0,
					MaxSize: 0,
					DesiredCapacity: 0
				});
			})
			.thenWait(3000)
			.thenTrue();
	}
}
