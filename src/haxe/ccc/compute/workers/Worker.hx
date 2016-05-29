package ccc.compute.workers;

import js.Node;
import js.npm.RedisClient;
import js.npm.Ssh;
import js.npm.Docker;

import promhx.Promise;
import promhx.Stream;
import promhx.PublicStream;
import promhx.deferred.DeferredPromise;
import promhx.deferred.DeferredStream;
import promhx.CallbackPromise;

import ccc.compute.Definitions;
import ccc.compute.InstancePool;
import ccc.compute.ComputeQueue;

import util.DockerTools;
import util.RedisTools;

using promhx.PromiseTools;
using Lambda;

enum MachineConnectionStatus {
	Connecting;
	Connected;
	LostContact;
}

/**
 * Represents an virtual instance somewhere in the cloud or local.
 * The machine has docker running, and it typically CoreOS.
 * It maintains an SSH connection or docker websocket connection
 * to the machine for monitoring status.
 */
class Worker
{
	public var status (default, null) = PublicStream.publicstream(MachineConnectionStatus.Connecting);
	public var computeStatus (get, null) :MachineStatus;
	public var id (get, null) :MachineId;

	@inject public var _redis :RedisClient;
	var _definition :WorkerDefinition;
	var _id :MachineId;
	var _computeStatus :MachineStatus;
	var _docker :Docker;
	var _stateChangeStream :Stream<MachineStatus>;
	var _workerPoll :Stream<Bool>;
	var log :AbstractLogger;

	static var ALL_WORKERS = new Map<MachineId, Worker>();

	public function new(def :WorkerDefinition)
	{
		Assert.notNull(def);
		Assert.notNull(def.id);
		log = Logger.child({'instanceid':def.id, type:'worker'});
		Assert.that(!ALL_WORKERS.exists(def.id));
		ALL_WORKERS.set(def.id, this);
		_definition = def;
	}

	public function toString() :String
	{
		return 'WORKER[id=$id computeStatus=$computeStatus]';
	}

	@post public function postInject()
	{
		Assert.notNull(_redis.connectionOption);
		_id = _definition.id;
		_docker = new Docker(_definition.docker);

		var machineStateChannel = InstancePool.REDIS_KEY_WORKER_STATUS_CHANNEL_PREFIX + _id;
		_stateChangeStream = RedisTools.createStreamFromHash(_redis, machineStateChannel, InstancePool.REDIS_KEY_WORKER_STATUS, _id);
		_stateChangeStream.then(function(status) {
			if (status != null && status != _computeStatus) {
				_computeStatus = status;
				log.debug({'status':_computeStatus});
				if (_computeStatus == MachineStatus.Removing) {

				}
			}
		});
		startPoll();
	}

	function startPoll()
	{
		//Here is where we watch for terminated machines.
		//Breaking this out for readability
		var pollIntervalMilliseconds = 2000;
		var maxRetries = 3;
		var doublingRetryIntervalMilliseconds = 200;
		_workerPoll = WorkerTools.poll(
			function() {
				if (_docker != null && _computeStatus != Removing) {
					var promise = new CallbackPromise();
					_docker.ping(promise.cb1);
					return promise;
				} else {
					return Promise.promise(true);//We're disposed.
				}
			},
			pollIntervalMilliseconds,
			maxRetries,
			doublingRetryIntervalMilliseconds
		);
		_workerPoll.then(function(ok) {
			if (_redis != null && !ok) {
				log.warn({'status':_computeStatus, 'log':'Lost contact'});
				switch(_computeStatus) {
					case Available,Deferred,WaitingForRemoval:
						onMachineFailure();
					case Failed:
					case Removing:
						// InstancePool.removeInstance(_redis, _id);

				}
			}
		});
	}

	/**
	 * Lost contact with the machine, we assume it is
	 * dead, so re-queue jobs and remove this machine.
	 * @return [description]
	 */
	function onMachineFailure() :Promise<Bool>
	{
		log.warn({'status':_computeStatus, state:'FAILURE', 'log':'Machine failure, removing from InstancePool'});
		return InstancePool.workerFailed(_redis, _id);
	}

	/**
	 * Removes this machinefrom the database.
	 * WARNING: if false is false, this could take a while
	 * as it will wait for the assigned jobs to finish.
	 * @return [description]
	 */
	// public function removeMachine (?force :Bool = true) :Promise<Bool>
	// {
	// 	return Promise.promise(true)
	// 		.pipe(function(_) {
	// 			//This prevents any more jobs being added
	// 			return InstancePool.setInstanceStatus(_redis, _id, MachineStatus.Removing);
	// 		})
	// 		.pipe(function(_) {
	// 			return InstancePool.getJobCountOnMachine(_redis, _id);
	// 		})
	// 		.pipe(function(jobCount) {
	// 			if (jobCount == 0) {
	// 				return InstancePool.removeInstance(_redis, _id)
	// 					.thenTrue();
	// 			} else {
	// 				if (force) {
	// 					return InstancePool.getJobsOnMachine(_redis, _id)
	// 						.pipe(function(computeJobIds) {
	// 							//In between the first check and the second, it went from >0 jobs to
	// 							//0 jobs so it's safe to remove
	// 							if (js.npm.RedisTools.isArrayObjectEmpty(computeJobIds)) {
	// 								return InstancePool.removeInstance(_redis, _id)
	// 									.thenTrue();
	// 							} else {
	// 								return Promise.whenAll(computeJobIds.map(
	// 									function(computeJobId) {
	// 										return ComputeQueue.requeueJob(_redis, null, computeJobId)
	// 											.thenTrue()
	// 											.errorPipe(function(err) {
	// 												Log.error('Failed to requeue job $computeJobId');
	// 												return Promise.promise(true);
	// 											});
	// 									}))
	// 									.pipe(function(_) {
	// 										return InstancePool.removeInstance(_redis, _id);
	// 									})
	// 									.thenTrue();
	// 							}
	// 						});
	// 				} else {
	// 					//Ugh. Let's wait until the damn jobs have finished.
	// 					//No, let's just return FALSE
	// 					return Promise.promise(false);
	// 				}
	// 			}
	// 		});
	// }

	/**
	 * Doesn't actually do anything to the underlying instance, just
	 * cleans up this object.
	 * @return [description]
	 */
	public function dispose()
	{
		Log.warn({'status':_computeStatus, 'log':'dispose'});
		if (_redis == null) {
			return Promise.promise(true);
		}
		ALL_WORKERS.remove(_id);
		_redis = null;
		_definition = null;
		_id = null;
		_docker = null;
		_stateChangeStream.end();
		_stateChangeStream = null;
		if (_workerPoll != null) {
			_workerPoll.end();
			_workerPoll = null;
		}
		log = null;
		return Promise.promise(true);
	}

	public function setDefinition(def :WorkerDefinition)
	{
		_definition = def;
		return this;
	}

	inline function get_id() :MachineId
	{
		return _id;
	}

	inline function get_computeStatus() :MachineStatus
	{
		return _computeStatus;
	}
}