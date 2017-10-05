package ccc.lambda;

import js.npm.aws_sdk.EC2;
import js.npm.aws_sdk.AutoScaling;

using ccc.RedisLoggerTools;

@:enum
abstract ScalingType(String) {
  var Up = 'Up';
  var Down = 'Down';
}

class LambdaScalingAws
	extends LambdaScaling
{
	static var BNR_ENVIRONMENT :String  = Node.process.env.get('BNR_ENVIRONMENT');
	static var redisUrl :String = 'redis-ccc.${BNR_ENVIRONMENT}.bionano.bio';
	static var AppTagValue = 'cloudcomputecannon';
	var _AutoScalingGroup :AutoScalingGroup = null;
	var AutoScalingGroupName :String = null;

	var autoscaling = new AutoScaling();
	var ec2 = new EC2();

	@:expose('handlerScaleUp')
	public static function handlerScaleUp(event :Dynamic, context :Dynamic, callback :js.Error->Dynamic->Void)
	{
		handlerScale(ScalingType.Up, event, context, callback);
	}

	@:expose('handlerScaleDown')
	public static function handlerScaleDown(event :Dynamic, context :Dynamic, callback :js.Error->Dynamic->Void) :Void
	{
		handlerScale(ScalingType.Down, event, context, callback);
	}

	static function handlerScale(scalingType :ScalingType, event :Dynamic, context :Dynamic, callback :js.Error->Dynamic->Void) :Void
	{
		trace('handlerScale${scalingType}');
		var redis = LambdaScaling.getRedis(redisUrl);
		redis.infoLog('handlerScale${scalingType}');
		var calledBack = false;
		redis.on(RedisEvent.Error, function (err) {
			trace(err);
			// redis.errorEventLog(err, 'handlerScale${scalingType} redis error');
			// if (!calledBack) {
			// 	calledBack = true;
			// 	callback(err, null);
			// }
		});

		var scaler = new LambdaScalingAws().setRedis(redis);
		var scalePromise = switch(scalingType) {
			case Up: scaler.scaleUp();
			case Down: scaler.scaleDown();
		}
		scalePromise
			.then(function(data) {
				redis.infoLog({message:'Finished successfully', data: data});
				if (!calledBack) {
					redis.publish(RedisLoggerTools.REDIS_KEY_LOGS_CHANNEL, 'logs');
					redis.once('end', function() {
						if (!calledBack) {
							calledBack = true;
							callback(null, data);
						}
					});
					redis.quit();
				}
			})
			.catchError(function(err) {
				redis.infoLog({message:'Finished with error'});
				redis.errorEventLog(err);
				redis.publish(RedisLoggerTools.REDIS_KEY_LOGS_CHANNEL, 'logs');
				redis.once('end', function() {
					if (!calledBack) {
						calledBack = true;
						callback(err, null);
					}
				});
				redis.quit();
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
				redis.debugLog(params);
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
				redis.debugLog({asg:asg});
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
		return getAutoScalingGroup(false)
			.then(function(asg :AutoScalingGroup) {
				return asg.AutoScalingGroupName;
			});
	}

	function getAutoScalingGroup(?disableCache :Bool = true) :Promise<AutoScalingGroup>
	{
		if (!disableCache && _AutoScalingGroup != null) {
			return Promise.promise(_AutoScalingGroup);
		} else {
			var promise = new DeferredPromise();
			var params :DescribeAutoScalingGroupsParams = {};
			//Even if cache is disabled, caching the name will go faster
			if (AutoScalingGroupName != null) {
				params.AutoScalingGroupNames = [AutoScalingGroupName];
			}
			autoscaling.describeAutoScalingGroups(params, function(err, data) {
				if (err != null) {
					redis.errorEventLog(err);
					promise.boundPromise.reject(err);
					return;
				}
				var asgs = data.AutoScalingGroups != null ? data.AutoScalingGroups : [];
				var cccAutoScalingGroup = null;
				for (asg in asgs) {
					if (cccAutoScalingGroup != null) {
						break;
					}
					var tags = asg.Tags;

					if (tags != null) {
						var isCorrectEnv = tags.exists(function(tag) {return tag.Key == 'environment' && tag.Value.startsWith(BNR_ENVIRONMENT);});
						var isCorrectApp = tags.exists(function(tag) {return tag.Key == 'app' && tag.Value.startsWith(AppTagValue);});
						if (isCorrectEnv && isCorrectApp) {
							cccAutoScalingGroup = asg;
							AutoScalingGroupName = asg.AutoScalingGroupName;
						}
					}
				}
				redis.debugLog({cccAutoScalingGroup: cccAutoScalingGroup});
				if (cccAutoScalingGroup != null) {
					_AutoScalingGroup = cccAutoScalingGroup;
				}
				promise.resolve(_AutoScalingGroup);
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

	function getInstanceMinutesSinceLaunch(instanceId :MachineId) :Promise<Int>
	{
		return getInstanceInfo(instanceId)
			.then(function(info :Dynamic) {
				var minutes :Int = -1;
				if (info != null) {
					var launchDate = Date.fromTime(info.LaunchTime);
					var instanceTime = launchDate.getTime();
					var now = Date.now().getTime();
					var diff = now - instanceTime;
					var seconds = diff / 1000;
					minutes = Std.int(seconds / 60);
				}
				return minutes;
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
		redis.debugLog('removeUnhealthyWorkers');
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
											redis.infoLog({instanceId:instanceId, message:'Terminating ${instanceId}', status:healthString, minutesSinceLaunch:minutesSinceLaunch});
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