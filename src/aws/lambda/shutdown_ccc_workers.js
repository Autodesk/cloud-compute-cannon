'use strict';

//Take this out when running in the cloud
var LOCAL = false;

if (LOCAL) {
    require('dotenv').config();
}

const AWS = require('aws-sdk');
if (LOCAL) {
    AWS.config.update({region: 'us-west-2'});
}

var ec2 = new AWS.EC2();

function getInstanceData(instances, instanceId) {
    for (var i = 0; i < instances.Reservations.length; i++) {
        for (var j = 0; j < instances.Reservations[i].Instances.length; j++) {
            var instanceData = instances.Reservations[i].Instances[j];
            if (instanceData.InstanceId == instanceId) {
                return instanceData;
            }
        }
    }
    return null;
}

function checkWorker(workerId, ownerId, instances, cb) {
    var serverData = getInstanceData(instances, ownerId);
    var serverName = serverData !== null ? '[' + ownerId + ', ' + serverData.State.Name + ']' : 'missing';
    console.log('Found worker=' + workerId + ' with owner=' + serverName);
    if (serverData === null || serverData.State.Name != 'running') {
        console.log('Server not running for worker=' + workerId + ' server=' + serverName);
        ec2.terminateInstances({InstanceIds:[workerId], DryRun: true}, (err, data) => {
            if (err) {
                console.error(err);
            } else {
                console.log(data);
            }
            cb(workerId);
        });
    } else {
        cb(workerId);
    }
}

exports.handler = function(event, context, callback) {
    ec2.describeInstances(null, (err, instances) => {
        if (err) {
            console.log('Failed to run ec2.describeInstances', err);
            console.error(err);
        } else {
            var workersToCheck = [];
            for (var i = 0; i < instances.Reservations.length; i++) {
                var instanceData = instances.Reservations[i];//Because we only ever create a single instance per API call.
                instanceData = instanceData.Instances[0];
                if (instanceData.State.Name == 'running') {
                    var InstanceId = instanceData.InstanceId;
                    var Tags = instanceData.Tags;
                    var isWorker = false;
                    var serverOwner = null;
                    for (var j = 0; j < Tags.length; j++) {
                        var key = Tags[j].Key;
                        var value = Tags[j].Value;
                        if (key == 'CCC_TYPE' && value == 'worker') {
                            isWorker = true;
                        }
                        if (key == 'CCC_OWNER') {
                            serverOwner = value;
                        }
                    }
                    if (isWorker) {
                        workersToCheck.push(InstanceId);
                        checkWorker(InstanceId, serverOwner, instances, (workerId) => {
                            var index = workersToCheck.indexOf(workerId);
                            if (index > -1) {
                                workersToCheck.splice(index, 1);
                            }
                            if (workersToCheck.length === 0) {
                                if (callback !== undefined) {
                                    callback(null, "Done");
                                }
                            }
                        });
                    }
                }
            }
            if (workersToCheck.length === 0) {
                if (callback !== undefined) {
                    callback(null, "No orphaned workers found");
                }
            }
        }
    });
}

if (LOCAL) {
    exports.handler();
}