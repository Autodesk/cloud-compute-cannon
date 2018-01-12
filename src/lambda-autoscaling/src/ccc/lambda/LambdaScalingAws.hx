package ccc.lambda;

import js.npm.aws_sdk.EC2;
import js.npm.aws_sdk.AutoScaling;

using ccc.RedisLoggerTools;

class LambdaScalingAws
	extends LambdaScaling
{
	static var REDIS_HOST :String  = Node.process.env.get('REDIS_HOST');
	static var ASG_NAME :String  = Node.process.env.get('ASG_NAME');
	var _AutoScalingGroup :AutoScalingGroup = null;

	var autoscaling = new AutoScaling();
	var ec2 = new EC2();

	@:expose('handlerScale')
	static function handlerScale(event :Dynamic, context :Dynamic, callback :js.Error->Dynamic->Void) :Void
	{
		trace('initializing redis and getting asg');
		var redis :RedisClient;
		var calledBack = false;
		LambdaScaling.getRedisClient({host:REDIS_HOST, port:6379})
			.pipe(function(client) {
				redis = client;
				trace('Got redis client!');

				var scaler = new LambdaScalingAws().setRedis(redis);

				return scaler.scale()
					.then(function(scaleResult) {
						trace('finished scaleResult=${Json.stringify(scaleResult)}');
						try {
							redis.infoLog({message:'Finished successfully', scaleResult: scaleResult});
							if (!calledBack) {
								redis.publish(RedisLoggerTools.REDIS_KEY_LOGS_CHANNEL, 'logs');
								redis.quit();
							}
						} catch (err :Dynamic) {

						}
						if (!calledBack) {
							calledBack = true;
							callback(null, 'finished ${Json.stringify(scaleResult)}');
						}
					});
			})
			.catchError(function(err) {
				trace('ERROR ' + err);
				try {
					redis.infoLog({message:'Finished with error'});
					redis.errorEventLog(cast err);
					redis.publish(RedisLoggerTools.REDIS_KEY_LOGS_CHANNEL, 'logs');
					redis.quit();
				} catch(err :Dynamic) {
					//Ignored
					trace(err);
				}
				if (!calledBack) {
					calledBack = true;
					callback(cast err, null);
				}
			});
	}

	public function new()
	{
		super();
	}

	override public function setDesiredCapacity(desiredWorkerCount :Int) :Promise<String>
	{
		return getAutoScalingGroup()
			.pipe(function(asg :AutoScalingGroup) {
				var promise = new DeferredPromise();
				var params = {
					AutoScalingGroupName: asg.AutoScalingGroupName,
					DesiredCapacity: desiredWorkerCount,
					HonorCooldown: true
				};
				redis.infoLog(LogFieldUtil.addWorkerEvent(Reflect.copy(params), WorkerEventType.SET_WORKER_COUNT));
				autoscaling.setDesiredCapacity(params, function(err, data) {
					if (err != null) {
						promise.boundPromise.reject(err);
					} else {
						promise.resolve('Increased DesiredCapacity ${asg.DesiredCapacity} => ${desiredWorkerCount}');
					}
				});
				return promise.boundPromise;
			});
	}

	/**
	 * This does not remove workers with running jobs
	 * @return [description]
	 */
	function scaleDownToMinimumWorkers()
	{
		return getAutoScalingGroup()
			.pipe(function(asg) {
				var NewDesiredCapacity = asg.MinSize;
				var instancesToKill = asg.DesiredCapacity - NewDesiredCapacity;
				redis.debugLog({
					op: "ScaleDown",
					MinSize: asg.MinSize,
					MaxSize: asg.MaxSize,
					DesiredCapacity: asg.DesiredCapacity,
					NewDesiredCapacity: NewDesiredCapacity,
					instancesToKill: asg.DesiredCapacity - NewDesiredCapacity
				});
				if (instancesToKill > 0) {
					return removeIdleWorkers(instancesToKill)
						.then(function(actualInstancesKilled) {
							return "Actual instaces killed: " + Json.stringify(actualInstancesKilled);
						});
				} else {
					return Promise.promise("No change needed");
				}
			});
	}

	override function getInstanceIds() :Promise<Array<String>>
	{
		return getAutoScalingGroup()
			.then(function(asg :AutoScalingGroup) {
				return asg.Instances.map(function(i) {
					return i.InstanceId;
				});
			});
	}

	override function getMinMaxDesired() :Promise<MinMaxDesired>
	{
		return getAutoScalingGroup()
			.then(function(asg :AutoScalingGroup) {
				return {
					MinSize: asg.MinSize,
					MaxSize: asg.MaxSize,
					DesiredCapacity: asg.DesiredCapacity
				};
			});
	}

	/**
	 * Returns the AutoScalingGroup name with the
	 * tag: stack=<stackKeyValue>
	 */
	function getAutoScalingGroupName() :Promise<String>
	{
		return getAutoScalingGroup()
			.then(function(asg :AutoScalingGroup) {
				return asg.AutoScalingGroupName;
			});
	}

	function getAutoScalingGroup() :Promise<AutoScalingGroup>
	{
		if (_AutoScalingGroup != null) {
			return Promise.promise(_AutoScalingGroup);
		} else {
			var promise = new DeferredPromise();
			var params :DescribeAutoScalingGroupsParams = {
				AutoScalingGroupNames: [ASG_NAME]
			};
			redis.infoLog(params);
			redis.infoLog('autoscaling.describeAutoScalingGroups');

			var isResolved = false;
			var cleanup = null;
			var timeoutId = Node.setTimeout(function() {
				trace('describeAutoScalingGroups timed out');
				cleanup(new js.Error('describeAutoScalingGroups timed out'), null);
			}, 15000);//Timeout after 15 seconds

			cleanup = function(err, data) {
				if (isResolved) {
					return;
				}
				if (err != null) {
					promise.boundPromise.reject(err);
				} else {
					promise.resolve(data);
				}
				isResolved = true;
				if (timeoutId != null) {
					Node.clearTimeout(timeoutId);
				}
				timeoutId = null;
			}
			autoscaling.describeAutoScalingGroups(params, function(err, data) {
				trace('describeAutoScalingGroups returned');
				if (err != null) {
					trace('error, rejecting');
					trace(err);
					redis.errorEventLog(err);
					cleanup(err, null);
					return;
				}
				redis.infoLog('describeAutoScalingGroups data=${Json.stringify(data).substr(0, 100)}');
				redis.infoLog('describeAutoScalingGroups err=$err');
				var asgs = data.AutoScalingGroups != null ? data.AutoScalingGroups : [];
				if (asgs[0] != null) {
					_AutoScalingGroup = asgs[0];
				}
				redis.infoLog({cccAutoScalingGroup: _AutoScalingGroup});
				cleanup(null, _AutoScalingGroup);
			});

			return promise.boundPromise;
		}
	}

	function getInstanceMinutesBillingCycleRemaining(instanceId :MachineId) :Promise<Float>
	{
		return getInstanceInfo(instanceId)
			.then(function(info) {
				var remainingMinutes = null;
				if (info != null) {
					var launchDate = Date.fromTime(info.LaunchTime);
					var instanceTime = launchDate.getTime();
					var now = Date.now().getTime();
					var diff = now - instanceTime;
					var seconds = diff / 1000;
					var minutes = seconds / 60;
					var hours = minutes / 60;
					var minutesBillingCycle = minutes % 60;
					remainingMinutes = 60 - minutesBillingCycle;
				}
				return remainingMinutes;
			});
	}

	override function getTimeSinceInstanceStarted(instanceId :MachineId) :Promise<Float>
	{
		return getInstanceInfo(instanceId)
			.then(function(info :Dynamic) {
				if (info == null) {
					return -1.0;
				}
				trace('getTimeSinceInstanceStarted $instanceId ${Json.stringify(info, null, "  ")}');
				// var launchTime = Date.fromTime(info.LaunchTime);
				var now = Date.now().getTime();
				return now - info.LaunchTime;
			});
	}


	function getInstanceMinutesSinceLaunch(instanceId :MachineId) :Promise<Float>
	{
		return getTimeSinceInstanceStarted(instanceId)
			.then(function(time) {
				return (time / 1000) / 60;
			});
	}

	var instanceInfos :DynamicAccess<Dynamic> = {}
	function getInstanceInfo(instanceId :String, ?disableCache :Bool = false) :Promise<Dynamic>
	{
		if (!disableCache && instanceInfos.get(instanceId) != null) {
			return Promise.promise(instanceInfos.get(instanceId));
		} else {
			var promise = new DeferredPromise();
			var params = {
				InstanceIds: [instanceId]
			};
			ec2.describeInstances(params, function(err :js.Error, data :Dynamic) :Void {
				if (err != null) {
					promise.boundPromise.reject(err);
				} else {
					var instanceData = data && data.Reservations && data.Reservations[0] && data.Reservations[0].Instances && data.Reservations[0].Instances[0];
					instanceInfos.set(instanceId, instanceData);
					promise.resolve(instanceData);
				}
			});
			return promise.boundPromise;
		}
	}

	override function isInstanceCloseEnoughToBillingCycle(instanceId :String) :Promise<Bool>
	{
		return getInstanceMinutesBillingCycleRemaining(instanceId)
			.then(function(remainingMinutes :Float) {
				redis.debugLog({instanceId:instanceId, message: 'remainingMinutes in billing cycle=${remainingMinutes}'});
				return remainingMinutes <= 15;
			});
	}

	override function removeIdleWorkers(maxWorkersToRemove :Int) :Promise<Array<String>>
	{
		redis.infoLog({f:'removeIdleWorkers', maxWorkersToRemove:maxWorkersToRemove});
		var actualInstancesTerminated :Array<String> = [];
		return getInstancesReadyForTermination()
			.pipe(function(workersReadyToDie) {
				redis.debugLog({f:'removeIdleWorkers', workersReadyToDie:workersReadyToDie});
				while (workersReadyToDie.length > maxWorkersToRemove) {
					workersReadyToDie.pop();
				}
				return Promise.whenAll(workersReadyToDie.map(function(instanceId) {
					return getAutoScalingGroupName()
						.pipe(function(asgName) {
							var promise = new DeferredPromise();
							var params = {
								InstanceId: instanceId,
								ShouldDecrementDesiredCapacity: true
							};
							redis.debugLog({f:'removeIdleWorkers', message: 'terminateInstanceInAutoScalingGroup', params:params});
							actualInstancesTerminated.push(instanceId);
							autoscaling.terminateInstanceInAutoScalingGroup(params, function(err, data) {
								if (err != null) {
									promise.boundPromise.reject(err);
								} else {
									redis.debugLog({f:'removeIdleWorkers', message: 'Removed ${instanceId} and decremented asg'});
									promise.resolve(data);
								}
							});
							return promise.boundPromise;
						});
				}));
			})
			.then(function(_) {
				return actualInstancesTerminated;
			});
	}

	override function removeUnhealthyWorkers() :Promise<Bool>
	{
		trace('removeUnhealthyWorkers');
		return getAutoScalingGroup()
			.pipe(function(asg) {
				if (asg == null) {
					redis.infoLog('removeUnhealthyWorkers asg == null');
					return Promise.promise(false);
				}
				//Only concern ourselves with healthy instances.
				var instances = asg.Instances.filter(function(instanceData) {
					return instanceData.LifecycleState == "InService" && instanceData.HealthStatus == "Healthy";
				});

				var promises :Array<Promise<Bool>> = instances.map(function(instance :{InstanceId:MachineId}) {
					var instanceId :MachineId = instance.InstanceId;
					return getInstancesHealthStatus(instanceId)
						.pipe(function(healthString) {
							if (healthString != 'OK') {
								redis.infoLog({instanceId:instanceId, healthString:healthString});
								return getInstanceMinutesSinceLaunch(instanceId)
									.pipe(function(minutesSinceLaunch) {
										if (minutesSinceLaunch > 10) {
											redis.infoLog({instanceId:instanceId, message:'Terminating ${instanceId} health status != OK', status:healthString, minutesSinceLaunch:minutesSinceLaunch});
											return terminateWorker(instanceId)
												.then(function(_) {
													return true;
												});
										} else {
											redis.infoLog({instanceId:instanceId, message:'NOT Terminating ${instanceId}', status:healthString, minutesSinceLaunch:minutesSinceLaunch});
											return Promise.promise(true);
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

	override public function terminateWorker(id :MachineId) :Promise<Bool>
	{
		return super.terminateWorker(id)
			.pipe(function(_) {
				var promise = new DeferredPromise();
				var params = { InstanceIds: [id] };
				redis.infoLog({f:'terminateInstances', instanceId:id});
				ec2.terminateInstances(params, function(err, data) {
					if (err != null) {
						redis.errorEventLog(err, 'ec2.terminateInstances');
						promise.boundPromise.reject(err);
					} else {
						promise.resolve(true);
					}
				});
				return promise.boundPromise;
			});
	}


}