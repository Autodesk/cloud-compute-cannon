var Redis = require("redis");
var AWS = require('aws-sdk');
var Promise = require('bluebird');

var BNR_ENV_TAG = process.env['BNR_ENV_TAG'];
var redisUrl = 'redis.' + BNR_ENV_TAG + '.bionano.bio';
var StackTagValue = BNR_ENV_TAG + '-ccc-v1';

var autoscaling = new AWS.AutoScaling();
var ec2 = new AWS.EC2();

var redis = Redis.createClient({host:redisUrl, port:6379});
var AutoscalingGroup = null;
var AutoscalingGroupName = null;
/**
 * Returns the AutoscalingGroup name with the
 * tag: stack=<stackKeyValue>
 */
function getAutoscalingGroupName() {
	return getAutoscalingGroup(false)
		.then(function(asg) {
			return asg['AutoScalingGroupName'];
		});
}

function getAutoscalingGroup(disableCache) {
	if (!disableCache && AutoscalingGroup) {
		return Promise.resolve(AutoscalingGroup);
	} else {
		return new Promise(function(resolve, reject) {
			var params = {};
			//Even if cache is disabled, caching the name will go faster
			if (AutoscalingGroupName) {
				params.AutoScalingGroupNames = [AutoscalingGroupName];
			}
			autoscaling.describeAutoScalingGroups(params, function(err, data) {
				if (err) {
					reject(err);
					return;
				}
				var asgs = data['AutoScalingGroups'];
				var cccAutoscalingGroup = null;
				for (var i = 0; i < asgs.length; i++) {
					if (cccAutoscalingGroup) {
						break;
					}
					var asg = asgs[i];
					var tags = asg['Tags'];
					if (tags) {
						for (var j = 0; j < tags.length; j++) {
							var tag = tags[j];
							if (tag['Key'] == 'stack' && tag['Value'] == StackTagValue) {
								cccAutoscalingGroup = asg;
								AutoscalingGroupName = asg.AutoscalingGroupName;
								break;
							}
						}
					}
				}
				if (cccAutoscalingGroup) {
					AutoscalingGroup = cccAutoscalingGroup;
				}
				resolve(AutoscalingGroup);
			});
		});
	}
}

function getQueueSize() {
	return new Promise(function(resolve, reject) {
		var queueName = 'job_queue';
		redis.llen("bull:" + queueName + ":wait", function(err, length){
		    if (err) {
				reject(err);
			} else {
				resolve(length);
			}
		});
	});
}

// function setCapacity(capacity) {
// 	return getAutoscalingGroupName()
// 		.then(function(scalingGroupName) {
// 			return new Promise(function(resolve, reject) {
// 				var params = {
// 					AutoScalingGroupName: scalingGroupName,
// 					DesiredCapacity: capacity,
// 					HonorCooldown: true
// 				};
// 				console.log(params);
// 				autoscaling.setDesiredCapacity(params, function(err, data) {
// 					if (err) {
// 						reject(err);
// 					} else {
// 						resolve(data);
// 					}
// 				});
// 			});
// 		})
// }

var instanceInfos = {}
function getInstanceInfo(instanceId, disableCache) {
	if (!disableCache && instanceInfos[instanceId]) {
		return Promise.resolve(instanceInfos[instanceId]);
	} else {
		return new Promise(function(resolve, reject) {
			var params = {
				InstanceIds: [instanceId]
			};
			ec2.describeInstances(params, function(err, data) {
				if (err) {
					reject(err);
				} else {
					var instanceData = data.Reservations[0].Instances[0];
					instanceInfos[instanceId] = instanceData;
					resolve(instanceData);
				}
			});
		});
	}
}

function getInstanceMinutesBillingCycleRemaining(instanceId) {
	return getInstanceInfo(instanceId)
		.then(function(info) {
			var launchDate = new Date(info.LaunchTime);
			var instanceTime = launchDate.getTime();
			var now = Date.now();
			var diff = now - instanceTime;
			var seconds = diff / 1000;
			var minutes = seconds / 60;
			var hours = minutes / 60;
			var minutesBillingCycle = minutes % 60;
			var remainingMinutes = 60 - minutesBillingCycle;
			return remainingMinutes;
		});
}

function getInstanceMinutesSinceLaunch(instanceId) {
	return getInstanceInfo(instanceId)
		.then(function(info) {
			var launchDate = new Date(info.LaunchTime);
			var instanceTime = launchDate.getTime();
			var now = Date.now();
			var diff = now - instanceTime;
			var seconds = diff / 1000;
			var minutes = seconds / 60;
			return minutes;
		});
}

function isInstanceCloseEnoughToBillingCycle(instanceId) {
	return getInstanceMinutesBillingCycleRemaining(instanceId)
		.then(function(remainingMinutes) {
			console.log(instanceId + ' remainingMinutes in billing cycle=' + remainingMinutes);
			return remainingMinutes <= 15;
		});
}

function getJobCount(instanceId) {
	return new Promise(function(resolve, reject) {
		var keyPrefix = 'ccc::jobs::worker_jobs::';
		redis.scard(keyPrefix + instanceId, function(err, count) {
			if (err) {
				console.error(err);
				reject(err);
			} else {
				resolve(count);
			}
		});
	});
}

function getInstanceIds() {
	return getAutoscalingGroup()
		.then(function(asg) {
			return asg.Instances.map(function(i) {
				return i.InstanceId;
			});
		});
}

function getInstancesReadyForTermination() {
	console.log('getInstancesReadyForTermination');
	return getInstanceIds()
		.then(function(instanceIds) {
			console.log('getInstancesReadyForTermination instanceIds', instanceIds);
			var workersReadyToDie = [];
			var promises = instanceIds.map(function(instanceId) {
				console.log('instanceId', instanceId);
				return getJobCount(instanceId)
					.then(function(count) {
						console.log(instanceId + " jobs=" + count);
						if (count == 0) {
							return isInstanceCloseEnoughToBillingCycle(instanceId)
								.then(function(okToTerminate) {
									if (okToTerminate) {
										workersReadyToDie.push(instanceId);
									} else {
										console.log('getInstancesReadyForTermination not ' + instanceId + ' because too close to billing cycle');
									}
									return true;
								});
						} else {
							console.log('getInstancesReadyForTermination not ' + instanceId + ' because job count=' + count);
							return true;
						}
					});
			});
			return Promise.all(promises)
				.then(function() {
					console.log('workersReadyToDie', workersReadyToDie);
					return workersReadyToDie;
				});
		});
}

function getInstancesHealthStatus(instanceId) {
	return new Promise(function(resolve, reject) {
		var keyPrefix = 'ccc::workers::worker_health_status::';
		var key = keyPrefix + instanceId;
		redis.get(key, function(err, healthString) {
			if (err) {
				console.error(err);
				reject(err);
			} else {
				resolve(healthString);
			}
		});
	});
}

function terminateInstance(instanceId) {
	return new Promise(function(resolve, reject) {
		var params = {InstanceIds: [instanceId]};
		console.log('terminateInstances', instanceId);
		ec2.terminateInstances(params, function(err, data) {
			if (err) {
				reject(err);
			} else {
				resolve(true);
			}
		});
	});
}

function removeUnhealthyWorkers() {
	console.log('removeUnhealthyWorkers');
	return getAutoscalingGroup()
		.then(function(asg) {
			//Only concern ourselves with healthy instances.
			var instances = asg.Instances.filter(function(instanceData) {
				return instanceData["LifecycleState"] == "InService" && instanceData["HealthStatus"] == "Healthy";
			});
			return Promise.all(instances.map(function(instance) {
				var instanceId = instance.InstanceId;
				return getInstancesHealthStatus(instanceId)
					.then(function(healthString) {
						if (healthString != 'OK') {
							console.log(instanceId + " != OK, status=" + healthString);
							return getInstanceMinutesSinceLaunch(instanceId)
								.then(function(minutesSinceLaunch) {
									if (minutesSinceLaunch > 10) {
										console.log("Terminating " + instanceId + " != OK, status=" + healthString + ", minutesSinceLaunch=" + minutesSinceLaunch);
										return terminateInstance(instanceId);
									} else {
										console.log("NOT terminating " + instanceId + " != OK, status=" + healthString + ", minutesSinceLaunch=" + minutesSinceLaunch);
										return true;
									}
								});
						} else {
							return true;
						}
					});
			}));
		});
}

function removeIdleWorkers(maxWorkersToRemove) {
	console.log('removeIdleWorkers maxWorkersToRemove', maxWorkersToRemove);
	var actualInstancesTerminated = [];
	return getInstancesReadyForTermination()
		.then(function(workersReadyToDie) {
			console.log('workersReadyToDie', workersReadyToDie);
			while (workersReadyToDie.length > maxWorkersToRemove) {
				workersReadyToDie.pop();
			}
			return Promise.all(workersReadyToDie.map(function(instanceId) {
				return getAutoscalingGroupName()
					.then(function(asgName) {
						return new Promise(function(resolve, reject) {
							var params = {
								InstanceId: instanceId,
								ShouldDecrementDesiredCapacity: true
							};
							console.log('terminateInstanceInAutoScalingGroup', params);
							actualInstancesTerminated.push(instanceId);
							autoscaling.terminateInstanceInAutoScalingGroup(params, function(err, data) {
								if (err) {
									reject(err);
								} else {
									console.log('Removed ' + instanceId + ' and decremented asg');
									resolve(data);
								}
							})
						});
					})
			}));
		})
		.then(function() {
			return actualInstancesTerminated;
		});
}

exports.handlerScaleUp = function(event, context, callback) {
	console.log('handlerScaleUp');
	redis.on("error", function (err) {
		console.error(err, err.stack);
		callback(err);
	});
	getQueueSize()
		.then(function(queueLength) {
			console.log("queueLength=" + queueLength);
			if (queueLength > 0) {
				return getAutoscalingGroup()
					.then(function(asg) {
						console.log('asg', asg != null);
						// "MinSize": 2,
						// "MaxSize": 4,
						// "DesiredCapacity": 2,
						// "DefaultCooldown": 60,
						//This logic could probably be tweaked
						//If we have at least one in the queue, increase
						//the DesiredCapacity++
						console.log({
							op: "ScaleUp",
							MinSize: asg["MinSize"],
							MaxSize: asg["MaxSize"],
							DesiredCapacity: asg["DesiredCapacity"],
							queueLength: queueLength
						});

						var currentDesiredCapacity = asg["DesiredCapacity"];
						var newDesiredCapacity = currentDesiredCapacity + 1;
						console.log('newDesiredCapacity', newDesiredCapacity);
						if (newDesiredCapacity <= asg["MaxSize"] && asg["DesiredCapacity"] < asg["MaxSize"]) {
							return new Promise(function(resolve, reject) {
								var params = {
									AutoScalingGroupName: asg['AutoScalingGroupName'],
									DesiredCapacity: newDesiredCapacity,
									HonorCooldown: true
								};
								console.log(params);
								autoscaling.setDesiredCapacity(params, function(err, data) {
									if (err) {
										reject(err);
									} else {
										resolve("Increased DesiredCapacity " + asg["DesiredCapacity"] + " => " + newDesiredCapacity);
									}
								});
							});
						} else {
							return "No change";
						}
					});
			} else {
				return "No change";
			}
		})
		.then(function(data) {
			return removeUnhealthyWorkers()
				.then(function() {
					return data;
				});
		})
		.then(function(data) {
			callback(null, data);
		})
		.catch(function(err) {
			callback(err, null);
		});
};

exports.handlerScaleDown = function(event, context, callback) {
	console.log('handlerScaleDown');
	redis.on("error", function (err) {
		console.error(err, err.stack);
		callback(err);
	});
	getQueueSize()
		.then(function(queueLength) {
			console.log("queueLength=" + queueLength);
			if (queueLength == 0) {
				return getAutoscalingGroup()
					.then(function(asg) {
						console.log('asg', asg != null);
						var NewDesiredCapacity = asg["MinSize"];
						var instancesToKill = asg["DesiredCapacity"] - NewDesiredCapacity;
						console.log({
							op: "ScaleDown",
							MinSize: asg["MinSize"],
							MaxSize: asg["MaxSize"],
							DesiredCapacity: asg["DesiredCapacity"],
							queueLength: queueLength,
							NewDesiredCapacity: NewDesiredCapacity,
							instancesToKill: asg["DesiredCapacity"] - NewDesiredCapacity
						});
						if (instancesToKill > 0) {
							return removeIdleWorkers(instancesToKill)
								.then(function(actualInstancesKilled) {
									return "Actual instaces killed: " + JSON.stringify(actualInstancesKilled);
								});
						} else {
							return "No change needed";
						}
					});
			} else {
				return "No change needed";
			}
		})
		.then(function(data) {
			console.log('calling callback with', data);
			callback(null, data);
		})
		.catch(function(err) {
			callback(err, null);
		});
};

