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
/**
 * Returns the AutoscalingGroup name with the
 * tag: stack=<stackKeyValue>
 */
function getAutoscalingGroupName() {
	return getAutoscalingGroup()
		.then(function(asg) {
			return asg['AutoScalingGroupName'];
		});
}

function getAutoscalingGroup() {
	if (AutoscalingGroup) {
		return Promise.resolve(AutoscalingGroup);
	} else {
		return new Promise(function(resolve, reject) {
			autoscaling.describeAutoScalingGroups({}, function(err, data) {
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

function getConfigMax() {
	return new Promise(function(resolve, reject) {
		redis.hget("ccc_config", "workers_max", function(err, resultString){
		    if (err) {
				reject(err);
			} else {
				resultString = resultString + "";
				try {
					var result = parseInt(resultString);
					resolve(result);
				} catch(err) {
					reject(err);
				}
			}
		});
	});
}

function getConfigMin() {
	return new Promise(function(resolve, reject) {
		redis.hget("ccc_config", "workers_min", function(err, resultString){
		    if (err) {
				reject(err);
			} else {
				resultString = resultString + "";
				try {
					var result = parseInt(resultString);
					resolve(result);
				} catch(err) {
					reject(err);
				}
			}
		});
	});
}

function setCapacity(capacity) {
	return getAutoscalingGroupName()
		.then(function(scalingGroupName) {
			return new Promise(function(resolve, reject) {
				var params = {
					AutoScalingGroupName: scalingGroupName,
					DesiredCapacity: capacity,
					HonorCooldown: true
				};
				console.log(params);
				autoscaling.setDesiredCapacity(params, function(err, data) {
					if (err) {
						reject(err);
					} else {
						resolve(data);
					}
				});
			});
		})
}

// function getAllMachineIds() {
// 	return new Promise(function(resolve, reject) {
// 		redis.smembers('ccc::workers::workers', function(err, data) {
// 			if (err) {
// 				reject(err);
// 			} else {
// 				resolve(data);
// 			}
// 		});
// 	});
// }

// getInstanceMap() {
// 	return getAllMachineIds()
// 		.then(funtion(machineids) {
// 			return new Promise(function(resolve, reject) {
// 				var params = {InstanceIds: machineids};
// 				ec2.describeInstances(params, function(err, data) {
// 					if (err) {
// 						reject(err);
// 					} else {
// 						var result = {};
// 						if (data && data.Instances) {
// 							for (var i = 0; i < data.Instances.length; i++) {
// 								result[data.Instances[i].InstanceId] = data.Instances[i];
// 							}
// 						}
// 						resolve(result);
// 					}
// 				});
// 			});
// 		});
// }

// function getInstanceIp(instanceId) {
// 	return new Promise(function(resolve, reject) {
// 		var params = {
// 		  DryRun: true || false,
// 		  InstanceIds: [
// 		    'STRING_VALUE',
// 		    /* more items */
// 		  ],
// 		  MaxResults: 0,
// 		  NextToken: 'STRING_VALUE'
// 		};
// 		ec2.describeInstances(params, function(err, data) {
// 		  if (err) console.log(err, err.stack); // an error occurred
// 		  else     console.log(data);           // successful response
// 		});
// 	});
// }

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
				return getConfigMax()
					.then(function(configMax) {
						console.log('configMax', configMax);
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
									configMax: configMax,
									queueLength: queueLength
								});
								var currentDesiredCapacity = asg["DesiredCapacity"];
								var newDesiredCapacity = currentDesiredCapacity + 1;
								console.log('newDesiredCapacity', newDesiredCapacity);
								if (newDesiredCapacity < asg["MaxSize"]) {
									var params = {
										AutoScalingGroupName: asg['AutoScalingGroupName'],
										DesiredCapacity: newDesiredCapacity
										// HonorCooldown: true
									};
									console.log(params);
									return new Promise(function(resolve, reject) {
										autoscaling.updateAutoScalingGroup(params, function(err, data) {
											if (err) {
												reject(err);
											} else {
												resolve(data);
											}
										});
									});
								} else {
									return true;
								}
							});
					});
			} else {
				return true;
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
				return getConfigMin()
					.then(function(configMin) {
						console.log('configMin', configMin);
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
									op: "ScaleDown",
									MinSize: asg["MinSize"],
									MaxSize: asg["MaxSize"],
									DesiredCapacity: asg["DesiredCapacity"],
									configMin: configMin,
									queueLength: queueLength
								});
								// if (asg["DesiredCapacity"] > asg["MinSize"]) {
								// 	for (var i = 0; )
								// }
								var NewDesiredCapacity = asg["MinSize"];//Math.max(asg["MinSize"], configMin);
								if (NewDesiredCapacity > asg["DesiredCapacity"]) {
									console.log('DesiredCapacity', DesiredCapacity);
									var params = {
										AutoScalingGroupName: asg['AutoScalingGroupName'],
										// MaxSize: DesiredCapacity,
										DesiredCapacity: NewDesiredCapacity
									};
									console.log(params);
									return new Promise(function(resolve, reject) {
										autoscaling.updateAutoScalingGroup(params, function(err, data) {
											if (err) {
												reject(err);
											} else {
												resolve(data);
											}
										});
									});
								} else {
									return "No change needed";
								}
							});
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

