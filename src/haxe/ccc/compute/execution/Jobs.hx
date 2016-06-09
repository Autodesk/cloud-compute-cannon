package ccc.compute.execution;

/**
 * Manages jobs.
 * Right now assumes there is only one active process,
 * but this will be split out so than n processes can
 * run and will split the job load between them, since
 * the jobs are the most network and memory demanding
 * aspect of the scheduling system.
 */

import haxe.Json;

import js.Node;
import js.npm.RedisClient;
import js.npm.Ssh;
import js.npm.Docker;

import minject.Injector;

import ccc.compute.ComputeTools;
import ccc.compute.InstancePool;
import ccc.compute.Definitions;
import ccc.compute.Definitions.Constants.*;
import ccc.compute.ComputeQueue;
import ccc.compute.LogStreams;
import ccc.compute.execution.Job;
import ccc.storage.ServiceStorage;

import promhx.Promise;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.deferred.DeferredStream;
import promhx.RedisPromises;

import util.DockerTools;
import util.SshTools;
import util.RedisTools;

using StringTools;
using ccc.compute.JobTools;
using ccc.compute.ComputeTools;
using promhx.PromiseTools;
using Lambda;
using util.MapTools;

/**
 * Listens to worker channels and handles the
 * creation of worker jobs.
 * In the future this could be split out into
 * another process(s).
 */
class Jobs
{
	var _workerUpdateStream :Stream<String>;
	var _workerJobListeners = new Map<MachineId, Stream<Array<ComputeJobId>>>();
	var _machineJobs = new Map<MachineId, Set<ComputeJobId>>();
#if tests public #end
	var _jobs = new Map<ComputeJobId, Job>();
	@inject public var _redis :RedisClient;
	@inject public var _injector :Injector;
	var _disposed :Bool = false;

	public function new() {}

	public function toString() :String
	{
		var result :Dynamic = {};
		var jobIds = [];
		for(id in _jobs.keys()) {
			jobIds.push(id);
		}
		Reflect.setField(result, 'computeJobIds', jobIds);
		var machine2Job :Dynamic = {};
		for (machineId in _machineJobs.keys()) {
			Reflect.setField(machine2Job, machineId, _machineJobs[machineId].array());
		}
		Reflect.setField(result, 'workerJobs', machine2Job);

		return Json.stringify({"jobs":result}, null, '  ');
	}

	@post
	public function postInject()
	{
		/* This updates the list of workers. Job updates are partitioned by worker id */
		_workerUpdateStream = RedisTools.createStream(_redis, InstancePool.REDIS_CHANNEL_KEY_WORKERS_UPDATE);
		_workerUpdateStream.then(function(_) {
			if (_redis != null) {
				syncWorkers();
			} else {
				Log.error('But _redis == null ?');
			}
		});
		syncWorkers();
	}

	public function dispose() :Promise<Bool>
	{
		if (_disposed) {
			Log.error('Already disposed Jobs');
			return Promise.promise(true);
		} else {
			_disposed = true;
			_workerUpdateStream.end();
			return _workerUpdateStream
				.endThen(function(_) return true)
				.pipe(function(_) {
					_workerUpdateStream = null;
					var promises = [];
					for (listener in _workerJobListeners) {
						listener.end();
						promises.push(listener.endThen(
							function(_) {
								return true;
							}));
					}
					return Promise.whenAll(promises)
						.thenTrue();
				})
				.pipe(function(_) {
					var promises = [];
					for (job in _jobs) {
						promises.push(job.dispose());
					}
					return Promise.whenAll(promises)
						.thenTrue();
				});
		}
	}

	function syncWorkers() :Promise<Bool>
	{
		var promise = InstancePool.getAllWorkerIds(_redis)
			.pipe(function(workerIds :Array<MachineId>) {
				// trace('Jobs syncWorkers workerIds=$workerIds');
				if (_redis == null) {//In case we're shut down
					Log.warn('Ignoring worker->job update since Jobs thinks it is shut down');
					return Promise.promise(true);
				}
				// trace('Jobs syncWorkers workerIds=${workerIds}');
				var promises = [];
				for (id in workerIds) {
					if (!_workerJobListeners.exists(id)) {
						createWorkerJobWatcher(id);
					}
				}

				var targetSet = Set.createString(workerIds);
				for (id in _workerJobListeners.keys()) {
					if (!targetSet.has(id)) {
						// Log.info('Removing worker job watcher workerId=$id');
						var workerJobStreamToRemove = _workerJobListeners.get(id);
						_workerJobListeners.remove(id);
						workerJobStreamToRemove.end();
						var jobIds = _machineJobs.get(id);
						_machineJobs.remove(id);
						for (jobId in jobIds) {
							// Log.info('Worker removed, all jobs disposed Job=$jobId removing Job object');
							var job = _jobs[jobId];
							job.dispose();
							_jobs.remove(jobId);
						}
					}
				}
				return Promise.whenAll(promises)
					.thenTrue();
			});
		return promise;
	}

	function createWorkerJobWatcher(workerId :MachineId)
	{
		// Log.info('createWorkerJobWatcher $workerId');
		Assert.that(!_workerJobListeners.exists(workerId));
		// Log.info('Creating worker job watcher workerId=$workerId');
		//Create a stream that updates the ComputeJobIds of a given worker
		var jobsChannel = InstancePool.REDIS_KEY_WORKER_JOBS_PREFIX + workerId;
		var jobsKey = InstancePool.REDIS_KEY_WORKER_JOBS_PREFIX + workerId;

		function getWorkerComputeJobIds(_) :Promise<Array<ComputeJobId>> {
			if (_redis == null) {
				return Promise.promise([]);
			} else {
				var promise = new DeferredPromise();
				_redis.smembers(jobsKey, function(err, jobsIds) {
					if (err != null) {
						promise.throwError(err);
						return;
					}
					promise.resolve(cast jobsIds);
				});
				return promise.boundPromise;
			}
		}

		function updateWorkerJobs(computeJobIds :Array<ComputeJobId>) {
			// trace('updateWorkerJobs worker=$workerId computeJobIds=${computeJobIds}');
			// Log.info('worker=${(workerId + '').substr(0, 6)} workerjobs=$computeJobIds currentJobs=${_jobs.keys()}');
			/* Check if jobs need to be created */
			for (computeJobId in computeJobIds) {
				if (!_machineJobs[workerId].has(computeJobId)) {
					_machineJobs[workerId].add(computeJobId);
					// Log.info('Job=$computeJobId does not yet exist on worker=$workerId, creating');
					var job = createJob(computeJobId);
					// Log.info('Creating job=$computeId on machine=$_id');
					_injector.injectInto(job);
					_jobs.set(computeJobId, job);
				}
			}
			/* Check if jobs need to be destroyed */
			for (currentComputeJobId in _machineJobs[workerId]) {
				if (!computeJobIds.has(currentComputeJobId)) {
					var job = _jobs.get(currentComputeJobId);
					// Log.info('Job=$currentComputeJobId no longer associated with worker=$workerId, removing Job object');
					_jobs.remove(currentComputeJobId);
					_machineJobs[workerId].remove(currentComputeJobId);
					job.dispose();
				}
			}
		}

		var workerJobsStream :Stream<Array<ComputeJobId>> = RedisTools.createStreamCustom(_redis, jobsChannel, getWorkerComputeJobIds);
		_workerJobListeners.set(workerId, workerJobsStream);
		_machineJobs.set(workerId, Set.createString());
		workerJobsStream.then(updateWorkerJobs);
	}

	function createJob(computeJobId :ComputeJobId)
	{
		var job = new Job(computeJobId);
		if (_injector.hasMapping(ServiceStorage, BOOT2DOCKER_PROVIDER_STORAGE_PATH)) {
			var workerStorage = _injector.getValue(ServiceStorage, BOOT2DOCKER_PROVIDER_STORAGE_PATH);
			job._workerStorage = workerStorage;
		}
		return job;
	}
}
