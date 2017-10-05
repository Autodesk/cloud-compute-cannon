package ccc.lambda;

using ccc.RedisLoggerTools;
using ccc.compute.shared.LogEvents;

class LambdaScaling
{
	var redis :RedisClient;

	public static function getRedis(redisHost :String)
	{
		return Redis.createClient({host:redisHost, port:6379});
	}

	public function setRedis(r :RedisClient)
	{
		this.redis = r;
		return this;
	}

	public function new() {}

	public function initialChecks() :Promise<Bool>
	{
		return removeWorkersInActiveSetThatAreNotRunning()
			.pipe(function(_) {
				return terminateUnhealthyInstances();
			});
	}

	public function scaleDown() :Promise<String>
	{
		return initialChecks()
			.pipe(function(_) {
				return getQueueSize();
			})
			.pipe(function(queueLength) {
				redis.debugLog({queueLength:queueLength});
				if (queueLength == 0) {
					return getMinMaxDesired()
						.pipe(function(minMax) {
							redis.debugLog({minMax:minMax});
							var NewDesiredCapacity = minMax.MinSize;

							if (minMax.DesiredCapacity - NewDesiredCapacity > 0) {
								redis.infoLog({
									op: 'ScaleDown',
									current: minMax,
									queueLength: queueLength,
									NewDesiredCapacity: NewDesiredCapacity,
									instancesToKill: minMax.DesiredCapacity - NewDesiredCapacity
								}.add(LogEventType.WorkersDesiredCapacity));
								return setDesiredCapacity(NewDesiredCapacity)
									.pipe(function(resultStatememt) {
										return Promise.promise('${resultStatememt}');
									});
							} else {
								return Promise.promise('No change');
							}
						});
				} else {
					return Promise.promise("No change needed");
				}
			})
			.then(function(result) {
				return '$result';
			});
	}

	public function scaleUp() :Promise<String>
	{
		// traceCyan('scaleUp');
		return initialChecks()
			.pipe(function(_) {
				return getQueueSize();
			})
			.pipe(function(queueLength) {
				redis.infoLog({queueLength:queueLength});
				if (queueLength > 0) {
					return getMinMaxDesired()
						.pipe(function(minMax) {
							// "MinSize": 2,
							// "MaxSize": 4,
							// "DesiredCapacity": 2,
							// "DefaultCooldown": 60,
							//This logic could probably be tweaked
							//If we have at least one in the queue, increase
							//the DesiredCapacity++
							redis.debugLog({
								op: 'ScaleUp',
								MinSize: minMax.MinSize,
								MaxSize: minMax.MaxSize,
								DesiredCapacity: minMax.DesiredCapacity,
								queueLength: queueLength
							});


							var currentDesiredCapacity = minMax.DesiredCapacity;
							var newDesiredCapacity = currentDesiredCapacity + 1;
							// traceCyan('scaleUp newDesiredCapacity=$newDesiredCapacity minMax=${Json.stringify(minMax)}');
							redis.infoLog({newDesiredCapacity:newDesiredCapacity});
							if (newDesiredCapacity <= minMax.MaxSize && minMax.DesiredCapacity < minMax.MaxSize) {
								// traceGreen('setDesiredCapacity($newDesiredCapacity)');
								return setDesiredCapacity(newDesiredCapacity)
									.pipe(function(resultStatememt) {
										return Promise.promise('${resultStatememt}');
									});
							} else {
								return Promise.promise('No change');
							}
						});
				} else {
					return Promise.promise('No change');
				}
			})
			.pipe(function(data :String) {
				return removeUnhealthyWorkers()
					.pipe(function(_) {
						return Promise.promise('${data}');
					});
			});
	}

	public function terminateWorker(id :MachineId) :Promise<Bool>
	{
		return WorkerStateRedis.terminate(redis, id)
			.thenTrue();
	}

	public function setDesiredCapacity(workerCount :Int) :Promise<String>
	{
		throw 'override';
		return Promise.promise('override');
	}

	function removeWorkersInActiveSetThatAreNotRunning() :Promise<Bool>
	{
		return getInstanceIds()
			.pipe(function(instanceIds) {
				return RedisPromises.smembers(redis, WorkerStateRedis.REDIS_MACHINES_ACTIVE)
					.pipe(function(dbMembers) {
						var promises = [];
						// traceCyan('instanceIds=$instanceIds dbMembers=$dbMembers');
						for (dbInstanceId in dbMembers) {
							if (!instanceIds.has(dbInstanceId)) {
								// traceCyan('$dbInstanceId not running, removing from active set');
								promises.push(RedisPromises.srem(redis, WorkerStateRedis.REDIS_MACHINES_ACTIVE, dbInstanceId));
							}
						}
						return Promise.whenAll(promises)
							.thenTrue();
					});
			});
	}

	function terminateUnhealthyInstances() :Promise<Bool>
	{
		return RedisPromises.smembers(redis, WorkerStateRedis.REDIS_MACHINES_ACTIVE)
			.pipe(function(instanceIds) {
				var promises = [];
				for (id in instanceIds) {
					var key = '${REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}$id';
					promises.push(
						RedisPromises.get(redis, key)
							.pipe(function(healthStatus) {
								if (healthStatus == null || healthStatus != WorkerHealthStatus.OK) {
									// traceRed('scaling WORKER bad health status, terminating $id');
									return terminateWorker(id)
										.thenTrue();
								} else {
									return Promise.promise(true);
								}
							})
					);
				}
				return Promise.whenAll(promises)
					.thenTrue();
			});
	}

	/**
	 * Returns the actual ids of workers removed
	 * since you cannot remove workers with jobs
	 * running
	 * @param  maxWorkersToRemove :Int          [description]
	 * @return                    [description]
	 */
	public function removeIdleWorkers(maxWorkersToRemove :Int) :Promise<Array<String>>
	{
		throw 'override';
		return Promise.promise([]);
	}

	function getMinMaxDesired() :Promise<MinMaxDesired>
	{
		throw 'override';
		return Promise.promise(null);
	}

	function removeUnhealthyWorkers() :Promise<Bool>
	{
		redis.debugLog('removeUnhealthyWorkers');
		return getInstanceIds()
			.pipe(function(instanceIds) {
				var promises = instanceIds.map(function(instanceId) {
					return isInstanceHealthy(instanceId)
						.pipe(function(isHealthy) {
							if (!isHealthy) {
								//Double check, if the instance just started, it may not have had time
								//to initialize
								return getTimeSinceInstanceStarted(instanceId)
									.pipe(function(timeMilliseconds) {
										var timeSeconds = timeMilliseconds / 1000;
										if (timeSeconds < 20) {
											// traceGreen('Not terminating potentially sick worker since it just stared up $instanceId');
											return Promise.promise(true);
										} else {
											redis.infoLog({instanceId:instanceId, message:'Terminating ${instanceId}'});
											return terminateWorker(instanceId)
												.errorPipe(function(err) {
													redis.errorLog({error:err});
													return Promise.promise(true);
												})
												.then(function(_) {
													return true;
												});
										}
									});
							} else {
								return Promise.promise(true);
							}
						});
				});
				return Promise.whenAll(promises)
					.then(function(ignored) {
						return true;
					});
			})
			.then(function(ignored) {
				return true;
			});
	}

	function getQueueSize() :Promise<Int>
	{
		var promise = new DeferredPromise();
		redis.llen('bull:${BullQueueNames.JobQueue}:wait', function(err, length) {
			if (err != null) {
				promise.boundPromise.reject(err);
			} else {
				promise.resolve(length);
			}
		});
		return promise.boundPromise;
	}

	function getJobCount(instanceId :MachineId) :Promise<Int>
	{
		var promise = new DeferredPromise();
		redis.zcard('${REDIS_KEY_SET_PREFIX_WORKER_JOBS}${instanceId}', function(err, count) {
			if (err != null) {
				trace(err);
				redis.errorEventLog(err);
				promise.boundPromise.reject(err);
			} else {
				promise.resolve(count);
			}
		});
		return promise.boundPromise;
	}

	function getInstancesHealthStatus(instanceId :MachineId) :Promise<WorkerHealthStatus>
	{
		var promise = new DeferredPromise();
		var key = '${REDIS_KEY_PREFIX_WORKER_HEALTH_STATUS}${instanceId}';
		redis.get(key, function(err, healthString) {
			if (err != null) {
				trace(err);
				redis.errorEventLog(err);
				promise.boundPromise.reject(err);
			} else {
				promise.resolve(healthString.asString());
			}
		});
		return promise.boundPromise;
	}

	function isInstanceHealthy(instanceId :MachineId) :Promise<Bool>
	{
		var promise = new DeferredPromise();
		redis.hget(REDIS_MACHINE_LAST_STATUS, '$instanceId', function(err, status) {
			if (err != null) {
				trace(err);
				redis.errorEventLog(err);
				promise.boundPromise.reject(err);
			} else {
				promise.resolve(status.asString() == WorkerStatus.OK);
			}
		});
		return promise.boundPromise;
	}

	function getInstancesReadyForTermination() :Promise<Array<MachineId>>
	{
		redis.infoLog({f:'getInstancesReadyForTermination'});
		var workersReadyToDie :Array<String> = [];
		return getInstanceIds()
			.pipe(function(instanceIds) {
				redis.debugLog({f:'getInstancesReadyForTermination', instanceIds: instanceIds});
				var promises = instanceIds.map(function(instanceId) {
					redis.debugLog({f:'getInstancesReadyForTermination', instanceId: instanceId});
					return getJobCount(instanceId)
						.pipe(function(count) {
							redis.debugLog({f:'getInstancesReadyForTermination', instanceId: instanceId, jobs:count});
							if (count == 0) {
								return isInstanceCloseEnoughToBillingCycle(instanceId)
									.then(function(okToTerminate) {
										if (okToTerminate) {
											workersReadyToDie.push(instanceId);
										} else {
											redis.debugLog({f:'getInstancesReadyForTermination', instanceId: instanceId, message:'NOT because too close to billing cycle'});
										}
										return true;
									});
							} else {
								redis.debugLog({f:'getInstancesReadyForTermination', instanceId: instanceId, message:'NOT because job count=${count}'});
								return Promise.promise(true);
							}
						});
				});
				return Promise.whenAll(promises);
			})
			.then(function(_) {
				redis.debugLog({workersReadyToDie: workersReadyToDie});
				return workersReadyToDie;
			});
	}

	function getTimeSinceInstanceStarted(id :MachineId) :Promise<Float>
	{
		throw 'override';
		return Promise.promise(0.0);
	}

	function getInstanceIds() :Promise<Array<String>>
	{
		throw 'override';
		return Promise.promise([]);
	}

	function isInstanceCloseEnoughToBillingCycle(instanceId :String) :Promise<Bool>
	{
		throw 'override';
		return Promise.promise(true);
	}
}