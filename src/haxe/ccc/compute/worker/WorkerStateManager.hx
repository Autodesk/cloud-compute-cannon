package ccc.compute.worker;

import util.DockerTools;

class WorkerStateManager
{
	public var ready :Promise<Bool>;

	@inject public var _injector :Injector;
	@inject public var _redisClients :ServerRedisClient;
	@inject public var _docker :Docker;
	var _id :MachineId;
	var _redis :RedisClient;
	var _monitorTimerId :Dynamic;
	var log :AbstractLogger;

	@post
	public function postInject()
	{
		Assert.notNull(_redisClients);
		Assert.notNull(_redisClients.client);
		Assert.notNull(_docker);
		_redis = _redisClients.client;

		ready = WorkerStateRedis.init(_redisClients.client)
			.pipe(function(_) {
				return ccc.lambda.RedisLogGetter.init(_redisClients.client);
			})
			.pipe(function(_) {
				return initializeThisWorker(_injector)
					.then(function(_) {
						_id = _injector.getValue(MachineId);
						log = Log.child({machineId:_id});
						var workerStatusStream = createWorkerStatusStream(_injector);

						workerStatusStream.then(function(workerState :WorkerState) {
							if (workerState.command != null) {
								switch(workerState.command) {
									case PauseHealthCheck:
										log.debug('Pausing health checks');
										pauseSelfMonitor();
									case UnPauseHealthCheck:
										log.debug('Resuming health checks');
										resumeSelfMonitor();
									case HealthCheck:
										log.debug('Manually triggered health check');
										registerHealthStatus();
									default://
								}
							}
						});

						//Listen to the redis log channel and when there
						//are new logs, grab them and forward them to the
						//fluent daemon (since it is harder for the lambda
						//scripts to send logs to fluent)
						var logStream = createRedisLogStream(_injector);
						logStream.then(function(logs) {
							if (logs != null && logs.length > 0) {
								for (logBlob in logs) {
									try {
										var level :String = logBlob.level;
										//If you don't delete this field, bunyan will NOT log it
										Reflect.deleteField(logBlob, 'level');
										//Convert time float to Date object
										if (Reflect.hasField(logBlob, 'time')) {
											Reflect.setField(logBlob, 'time', Date.fromTime(Reflect.field(logBlob, 'time')));
										}
										switch(level) {
											case RedisLoggerTools.REDIS_LOG_DEBUG: Log.debug(logBlob);
											case RedisLoggerTools.REDIS_LOG_INFO: Log.info(logBlob);
											case RedisLoggerTools.REDIS_LOG_WARN: Log.warn(logBlob);
											case RedisLoggerTools.REDIS_LOG_ERROR: Log.error(logBlob);
											default: Log.debug(logBlob);
										}
									} catch (err :Dynamic) {
										Log.warn('Failed to log $logBlob\n err=${Json.stringify(err)}');
									}
								}
							}
						});
						return true;
					})
					// .pipe(function(_) {
					// 	var processQueue = new ProcessQueue();
					// 	_injector.map(ProcessQueue).toValue(processQueue);
					// 	_injector.injectInto(processQueue);
					// 	return processQueue.ready;
					// })
					.then(function(_) {
						resumeSelfMonitor();
						registerHealthStatus();
						return true;
					});
			});
	}

	public function jobCount() :Promise<Int>
	{
		if (_id == null) {
			return Promise.promise(0);
		} else {
			return Jobs.getJobsOnWorker(_id)
				.then(function(jobList) {
					return jobList.length;
				});
		}
	}

	public function resumeSelfMonitor()
	{
		if (_monitorTimerId == null) {
			_monitorTimerId = Node.setInterval(function() {
				registerHealthStatus();
			}, ServerConfig.WORKER_STATUS_CHECK_INTERVAL_SECONDS * 1000);
		}
	}

	public function pauseSelfMonitor()
	{
		if (_monitorTimerId != null) {
			Node.clearInterval(_monitorTimerId);
			_monitorTimerId = null;
		}
	}

	public function registerHealthStatus() :Promise<Bool>
	{
		return getDiskUsage()
			.pipe(function(usage :Float) {
				return WorkerStateRedis.setDiskUsage(_id, usage)
					.then(function(_) {
						return usage;
					});
			})
			.pipe(function(usage :Float) {
				var ok = usage < 0.9;
				if (ok) {
					return setHealthStatus(WorkerHealthStatus.OK);
				} else {
					Log.error({message: 'Failed health check', status:WorkerHealthStatus.BAD_DiskFull});
					return setHealthStatus(WorkerHealthStatus.BAD_DiskFull);
				}
			})
			.errorPipe(function(err) {
				Log.error({error:err, message: 'Failed health check'});
				return setHealthStatus(WorkerHealthStatus.BAD_Unknown)
					.thenTrue()
					.errorPipe(function(err) {
						Log.error({error:err, f:'registerHealthStatus'});
						return Promise.promise(true);
					});
			});
	}

	public function setHealthStatus(status :WorkerHealthStatus) :Promise<Bool>
	{
		log.info(LogFieldUtil.addWorkerEvent({status:status}, status == WorkerHealthStatus.OK ? WorkerEventType.HEALTHY : WorkerEventType.UNHEALTHY));
		return WorkerStateRedis.setHealthStatus(_id, status);
	}

	function getDiskUsage() :Promise<Float>
	{
		return switch (ServerConfig.CLOUD_PROVIDER_TYPE) {
			case Local:
				// The local provider cannot actually check the local disk,
				// it is unknown where it should be mounted.
				Promise.promise(0.1);
			case AWS:
				getDockerDiskUsageAWS(_docker);
			default: throw 'Invalid CLOUD_PROVIDER_TYPE=${ServerConfig.CLOUD_PROVIDER_TYPE}, valid values: [${CloudProviderType.Local}, ${CloudProviderType.AWS}]';
		}
	}

	public function new() {}

	static function initializeThisWorker(injector :Injector) :Promise<Bool>
	{
		return getWorkerId(injector)
			.pipe(function(id) {
				injector.map(MachineId).toValue(id);
				var docker = injector.getValue(Docker);
				return DockerPromises.info(docker)
					.pipe(function(dockerinfo) {

						//The local 'worker' actually has a bunch of VCPUs,
						//but lets set this to 1 here otherwise it is not
						//really simulating a cloud worker
						switch(ServerConfig.CLOUD_PROVIDER_TYPE) {
							case Local: dockerinfo.NCPU = 1;
							case AWS:
						}

						return WorkerStateRedis.initializeWorker(id, dockerinfo);
					});
			});
	}

	static function createWorkerStatusStream(injector :Injector)
	{
		var redis :RedisClient = injector.getValue(RedisClient);
		var id :MachineId = injector.getValue(MachineId);
		var workerStatusStream :Stream<WorkerState> =
			RedisTools.createStreamCustom(
				redis,
				WorkerStateRedis.getWorkerStateNotificationKey(id),
				function(command :WorkerUpdateCommand) {
					return WorkerStateRedis.get(id)
						.then(function(workerState) {
							workerState.command = command;
							return workerState;
						});
				}
			);
		workerStatusStream.catchError(function(err) {
			Log.error({error:err, message: 'Failure on workerStatusStream'});
		});
		injector.map("promhx.Stream<ccc.WorkerState>", "WorkerStream").toValue(workerStatusStream);
		return workerStatusStream;
	}

	static function createRedisLogStream(injector :Injector) :Stream<Array<Dynamic>>
	{
		var redis :RedisClient = injector.getValue(RedisClient);
		var logStream :Stream<Array<Dynamic>> =
			RedisTools.createStreamCustom(
				redis,
				RedisLoggerTools.REDIS_KEY_LOGS_CHANNEL,
				function(ignored) {
					return ccc.lambda.RedisLogGetter.getLogs();
				}
			);
		logStream.catchError(function(err) {
			Log.error({error:err, message: 'Failure on logStream'});
		});
		return logStream;
	}


	static function getWorkerId(injector :Injector) :Promise<MachineId>
	{
		return switch(ServerConfig.CLOUD_PROVIDER_TYPE) {
			case Local:
				var docker = injector.getValue(Docker);
				var id :MachineId = DockerTools.getContainerId();
				return Promise.promise(id);
			case AWS:
				return RequestPromises.get('http://169.254.169.254/latest/meta-data/instance-id')
					.then(function(instanceId) {
						instanceId = instanceId.trim();
						return instanceId;
					});
			default: throw 'Invalid CLOUD_PROVIDER_TYPE=${ServerConfig.CLOUD_PROVIDER_TYPE}, valid values: [${CloudProviderType.Local}, ${CloudProviderType.AWS}]';
		}
	}

	static function getDockerDiskUsageAWS(docker :Docker) :Promise<Float>
	{
		var volumes :Array<MountedDockerVolumeDef> = [
			{
				mount: '/var/lib/docker',
				name: '/var/lib/docker'
			}
		];
		return DockerTools.runDockerCommand(docker, DOCKER_IMAGE_DEFAULT, ["df", "-h", "/var/lib/docker/"], null, volumes)
			.then(function(runResult) {
				var diskUse = ~/.*Mounted on\r\n.+\s+.+\s+.+\s+([0-9]+)%.*/igm;
				if (runResult.StatusCode == 0 && diskUse.match(runResult.stdout)) {
					var diskUsage = Std.parseFloat(diskUse.matched(1)) / 100.0;
					Log.debug({disk:diskUsage});
					return diskUsage;
				} else {
					Log.warn('getDockerDiskUsageAWS: Non-zero exit code or did not match regex: ${runResult}');
					return 1.0;
				}
			});
	}
}
