package ccc.compute;
/**
 * All the redis interactions for managing the worker
 * instances and the jobs assigned to them. This ensures
 * that all state is stored in the redis cluster, so
 * processes that operate on the instances+jobs can
 * be scaled, or be resumed if they crash.
 */

import haxe.Json;
import haxe.io.Bytes;

import js.npm.RedisClient;
import js.npm.redis.RedisLuaTools;

import promhx.Promise;
import promhx.deferred.DeferredPromise;
import promhx.RedisPromises;

import ccc.compute.ComputeTools;

import t9.abstracts.time.*;

import util.DateFormatTools;

using util.ArrayTools;
using DateTools;

/**
 * Various Typedefs and definitions.
 */

@:enum
abstract MachineStatus(String) {
	/**
	 * This worker is in the process of creation. Most metadata will not be available
	 */
	var Initializing = 'initializing';
	/**
	 * This worker is available for job submission
	 */
	var Available = 'available';
	/**
	 * There are no more jobs on the queue, so this worker
	 * is marked for removal after its own jobs are finished.
	 * No more jobs will be added to this worker.
	 */
	var WaitingForRemoval = 'waiting_for_removal';
	/**
	 * This worker is about to be immediately removed.
	 * It is assumed that all prior requirements have
	 * been performed (jobs removed etc)
	 */
	var Removing = 'removing';
	/**
	 * The worker can no longer be reached. After updating
	 * this status, the server process will begin
	 * the removal process.
	 */
	var Failed = 'failed';
	/**
	 * The worker has no jobs, and no jobs are available,
	 * but the billing cycle means it is more efficient
	 * to defer actually terminating this worker, in case
	 * more jobs appear on the queue.
	 * Only the WorkerProvider is allowed to change this status to Available.
	 */
	var Deferred = 'deferred';
	/**
	 * The worker no longer exists. Records are kept here to ensure instances
	 * are not lost in between crashes.
	 */
	var Terminated = 'terminated';
}

@:enum
abstract MachineAvailableStatus(String) {
	var Idle = 'idle';
	var Working = 'working';
	var MaxCapacity = 'max_capacity';
}

typedef StatusResult = {
	var id :MachineId;
	var status :MachineStatus;
	var availableStatus :MachineAvailableStatus;
}

typedef TargetMachineCount = Dynamic<Int>;

@:enum
abstract SubmissionFailure(String) {
	var NO_WORKERS = 'no_workers';//Currently unused.
	var WORKERS_FULL = 'workers_full';
}

typedef JobSubmissionResult = {
	var success :Bool;
	@:optional var machineId :MachineId;
	@:optional var failureReason :SubmissionFailure;
}

// typedef ProviderConfig = {>ProviderConfigBase,
// 	var id :MachinePoolId;
// }

class InstancePool
{
	inline public static var REDIS_COMPUTE_POOL_PREFIX = 'workerpool${Constants.SEP}';
	inline public static var DEFAULT_COMPUTE_POOL_SCORE = 1;

	public static function registerComputePool(client :RedisClient, pool :MachinePoolId, priority :WorkerPoolPriority, maxInstances :WorkerCount, minInstances :WorkerCount, billingIncrement :Minutes) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		client.multi([
			['zadd', REDIS_KEY_WORKER_POOL_PRIORITY, priority, pool],
			['hset', REDIS_KEY_WORKER_POOL_MAX_INSTANCES, pool, maxInstances + ''],
			['hset', REDIS_KEY_WORKER_POOL_MIN_INSTANCES, pool, minInstances + ''],
			['hset', REDIS_KEY_WORKER_POOL_BILLING_INCREMENT, pool, billingIncrement.toFloat() + '']
			]).exec(promise.cb2);

		return promise.pipe(function(_) {
			return evaluateLuaScript(client, SCRIPT_UPDATE_TOTAL_WORKER_COUNT, []);
		});
	}

	public static function getProviderConfig(client :RedisClient, providerId :ServiceWorkerProviderType) :Promise<ServiceConfigurationWorkerProvider>
	{
		var promise = new promhx.deferred.DeferredPromise();
		client.multi([
			['zscore', REDIS_KEY_WORKER_POOL_PRIORITY, providerId],
			['hget', REDIS_KEY_WORKER_POOL_MAX_INSTANCES, providerId],
			['hget', REDIS_KEY_WORKER_POOL_MIN_INSTANCES, providerId],
			['hget', REDIS_KEY_WORKER_POOL_BILLING_INCREMENT, providerId],
			]).exec(function(err, multireply) {
				var config :ServiceConfigurationWorkerProvider = {
					type: providerId,
					priority: multireply[0],
					maxWorkers: multireply[1],
					minWorkers: multireply[2],
					billingIncrement: new Minutes(multireply[3]),
				}
				promise.resolve(config);
			});

		return promise.boundPromise;

	}

	/**
	 * Returns the actual number of machines assigned to
	 * different worker pools, since some have a max.
	 * @param client :RedisClient [description]
	 * @param count  :Int         [description]
	 */
	public static function setTotalWorkerCount(client :RedisClient, count :WorkerCount) :Promise<Int>
	{
		Assert.notNull(count);
		return evaluateLuaScript(client, SCRIPT_SET_TOTAL_WORKER_COUNT, [count])
			.then(function(resultString) {
				return Std.parseInt(resultString + '');
			});
	}

	public static function getTargetWorkerCount(client :RedisClient, pool :MachinePoolId) :Promise<Int>
	{
		Assert.notNull(pool);
		return RedisPromises.get(client, REDIS_KEY_WORKER_POOL_TARGET_INSTANCES)
			.then(Json.parse)
			.then(function(result :Dynamic<Int>) {
				return Reflect.field(result, pool);
			});
	}

	public static function setPoolPriority(client :RedisClient, pool :MachinePoolId, priority :WorkerPoolPriority) :Promise<Int>
	{
		return RedisPromises.zadd(client, REDIS_KEY_WORKER_POOL_PRIORITY, priority, pool);
	}

	public static function getMaxInstances(client :RedisClient, pool :MachinePoolId) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		client.hget(REDIS_KEY_WORKER_POOL_MAX_INSTANCES, pool, promise.cb2);
		return promise
			.then(function(val) {
				try {
					return Std.parseInt(val + '');
				} catch (err :Dynamic) {
					Log.error(err);
					return 0;
				}
			});
	}

	public static function setMaxInstances(client :RedisClient, pool :MachinePoolId, count :WorkerCount) :Promise<Int>
	{
		var result;
		return RedisPromises.hset(client, REDIS_KEY_WORKER_POOL_MAX_INSTANCES, pool, count + '')
			.pipe(function(out) {
				result = out;
				return evaluateLuaScript(client, SCRIPT_UPDATE_TOTAL_WORKER_COUNT, []);
			})
			.then(function(_) {
				return result;
			});
	}

	public static function setMinInstances(client :RedisClient, pool :MachinePoolId, count :WorkerCount) :Promise<Int>
	{
		var result;
		return RedisPromises.hset(client, REDIS_KEY_WORKER_POOL_MIN_INSTANCES, pool, count + '')
			.pipe(function(out) {
				result = out;
				return evaluateLuaScript(client, SCRIPT_UPDATE_TOTAL_WORKER_COUNT, []);
			})
			.then(function(_) {
				return result;
			});
	}

	public static function getMinInstances(client :RedisClient, pool :MachinePoolId) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		client.hget(REDIS_KEY_WORKER_POOL_MIN_INSTANCES, pool, promise.cb2);
		return promise
			.then(function(val) {
				try {
					return Std.parseInt(val + '');
				} catch (err :Dynamic) {
					Log.error(err);
					return 0;
				}
			});
	}

	public static function getInstancesInPool(client :RedisClient, poolId :MachinePoolId) :Promise<Array<StatusResult>>
	{
		return evaluateLuaScript(client, SCRIPT_GET_WORKERS_IN_POOL, [poolId])
			.then(function(resultString) {
				if (resultString == null || resultString == '{}') {
					return [];
				} else {
					return Json.parse(resultString);
				}
			});
	}

	public static function getRemovedInstances(client :RedisClient) :Promise<Dynamic>
	{
		return RedisPromises.hgetall(client, REDIS_KEY_WORKER_REMOVED_RECORD);
	}

	public static function getWorker(client :RedisClient, id :MachineId) :Promise<WorkerDefinition>
	{
		return RedisPromises.hget(client, REDIS_KEY_WORKERS, id)
			.then(Json.parse);
	}

	public static function getAllWorkerIds(client :RedisClient) :Promise<Array<MachineId>>
	{
		return cast RedisPromises.hkeys(client, REDIS_KEY_WORKER_STATUS);
	}

	public static function getWorkerParameters(client :RedisClient, id :MachineId) :Promise<WorkerParameters>
	{
		return RedisPromises.hget(client, REDIS_KEY_WORKER_PARAMETERS, id)
			.then(Json.parse);
	}

	public static function setWorkerParameters(client :RedisClient, id :MachineId, params :WorkerParameters) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		client.hset(REDIS_KEY_WORKER_PARAMETERS, id, Json.stringify(params), promise.cb2);
		return promise;
	}

	public static function setDefaultWorkerParameters(client :RedisClient, providerId :MachinePoolId, params :WorkerParameters) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		client.hset(REDIS_KEY_POOL_WORKER_PARAMETERS, providerId, Json.stringify(params), promise.cb2);
		return promise;
	}

	public static function isAvailable(m :StatusResult) :Bool
	{
		return m.status == MachineStatus.Available;
	}

	public static function isStatus(status :Array<MachineStatus>) :StatusResult->Bool
	{
		return function(m :StatusResult) {
			return status.has(m.status);
		};
	}

	public static function toMachineStatus(m :StatusResult) :MachineStatus
	{
		return m.status;
	}

	public static function isAvailableStatus(status :MachineAvailableStatus) :StatusResult->Bool
	{
		return function(m :StatusResult) {
			return m.availableStatus == status;
		};
	}

	public static function addInstance(client :RedisClient, poolId :MachinePoolId, worker :WorkerDefinition, parameters :WorkerParameters, ?state :MachineStatus = MachineStatus.Available) :Promise<Bool>
	{
		if (state != MachineStatus.Initializing) {
			Assert.notNull(worker.docker);
			Assert.that(worker.docker.host != '');
		}
		return evaluateLuaScript(client, SCRIPT_ADD_MACHINE, [poolId, Json.stringify(worker), Json.stringify(parameters), state, Date.now().getTime()])
			.then(Json.parse);
	}

	public static function removeInstance(client :RedisClient, id :MachineId) :Promise<WorkerDefinition>
	{
		return evaluateLuaScript(client, SCRIPT_REMOVE_MACHINE, [id, Date.now().getTime()])
			.then(Json.parse);
	}

	public static function workerFailed(client :RedisClient, id :MachineId) :Promise<Bool>
	{
		return evaluateLuaScript(client, SCRIPT_MACHINE_FAILED, [id, Date.now().getTime()])
			.then(function(_) return true);
	}

	public static function removeInstances(client :RedisClient, poolId :MachinePoolId) :Promise<Array<MachineId>>
	{
		return evaluateLuaScript(client, SCRIPT_REMOVE_WORKERS, [poolId, Date.now().getTime()])
			.then(Json.parse);
	}

	public static function setWorkerStatus(client :RedisClient, id :MachineId, status :MachineStatus) :Promise<Bool>
	{
		return evaluateLuaScript(client, SCRIPT_SET_WORKER_STATUS, [id, status])
			.then(Json.parse);
	}

	public static function setWorkerDeferredToRemoving(client :RedisClient, id :MachineId) :Promise<Bool>
	{
		return evaluateLuaScript(client, SCRIPT_SET_WORKER_STATUS_DEFFERED_TO_REMOVING, [id])
			.then(Json.parse);
	}

	public static function getInstanceStatus(client :RedisClient, id :MachineId) :Promise<MachineStatus>
	{
		var promise = new promhx.CallbackPromise();
		client.hget(REDIS_KEY_WORKER_STATUS, id, promise.cb2);
		return promise;
	}

	public static function getAllWorkers(client :RedisClient) :Promise<Array<WorkerDefinition>>
	{
		var promise = new promhx.CallbackPromise();
		client.hgetall(REDIS_KEY_WORKERS, promise.cb2);
		return promise
			.then(function(out) {
				var data :haxe.DynamicAccess<WorkerDefinition> = cast out;
				var result :Array<WorkerDefinition> = [];
				for (key in data.keys()) {
					result.push(data[key]);
				}
				return result;
			});
	}

	public static function setWorkerTimeout(client :RedisClient, id :MachineId, time :TimeStamp) :Promise<Bool>
	{
		return evaluateLuaScript(client, SCRIPT_SET_WORKER_DEFERRED_TIMEOUT, [id, time.toFloat()])
			.then(function(_) {
				return true;
			});
	}

	public static function getWorkerTimeout(client :RedisClient, id :MachineId) :Promise<TimeStamp>
	{
		var promise = new promhx.CallbackPromise();
		client.zscore(REDIS_KEY_WORKER_DEFERRED_TIME, id, promise.cb2);
		return promise
			.then(function(timeFloat :Float) {
				return new TimeStamp(new Milliseconds(timeFloat));
			});
	}

	public static function getAllWorkerTimeouts(client :RedisClient, providerId :MachinePoolId) :Promise<Array<{id:MachineId, time:TimeStamp}>>
	{
		return evaluateLuaScript(client, SCRIPT_GET_ALL_WORKER_TIMEOUTS, [providerId])
			.then(Json.parse);
	}

	public static function getJobCountOnMachine(client :RedisClient, id :MachineId) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		client.scard(REDIS_KEY_WORKER_JOBS_PREFIX + id, promise.cb2);
		return promise;
	}

	public static function getJobsOnMachine(client :RedisClient, id :MachineId) :Promise<Array<ComputeJobId>>
	{
		var promise = new promhx.CallbackPromise();
		client.smembers(REDIS_KEY_WORKER_JOBS_PREFIX + id, cast promise.cb2);
		return promise;
	}

	public static function existsMachine(client :RedisClient, id :MachineId) :Promise<Bool>
	{
		var promise = new promhx.CallbackPromise();
		client.hget(REDIS_KEY_WORKER_STATUS, id, promise.cb2);
		return promise
			.then(function(status) {
				return status != null && status != '';
			});
	}

	public static function findMachineForJob(client :RedisClient, params :JobParams) :Promise<Null<MachineId>>
	{
		return evaluateLuaScript(client, SCRIPT_FIND_MACHINE_MATCHING_JOB, [Json.stringify(params)]);
	}

	public static function getMachineForJob(client :RedisClient, id :ComputeJobId) :Promise<Null<WorkerDefinition>>
	{
		return evaluateLuaScript(client, SCRIPT_GET_MACHINE_FOR_JOB, [id])
			.then(Json.parse);
	}

	public static function addJobToMachine(client :RedisClient, jobId :ComputeJobId, params :JobParams, machineId :MachineId) :Promise<Bool>
	{
		return evaluateLuaScript(client, SCRIPT_ADD_JOB_TO_MACHINE, [jobId, Json.stringify(params), machineId, Date.now().getTime()])
			.then(function(_) {
				return true;
			});
	}

	public static function removeJob(client :RedisClient, jobId :ComputeJobId) :Promise<Bool>
	{
		return evaluateLuaScript(client, SCRIPT_REMOVE_JOB, [jobId, Date.now().getTime()]);
	}

	public static function toJson(client :RedisClient) :Promise<InstancePoolJsonDump>
	{
		return evaluateLuaScript(client, SCRIPT_GET_JSON)
			.then(Json.parse);
	}

	public static function toRawJson(client :RedisClient) :Promise<Dynamic>
	{
		return evaluateLuaScript(client, SCRIPT_GET_RAW_JSON)
			.then(Json.parse);
	}

	public static function dumpJson(client :RedisClient) :Promise<InstancePoolJsonDump>
	{
		return toJson(client)
			.then(function(dump) {
				trace(dump);
				return dump;
			});
	}

	public static function init(redis :RedisClient) :Promise<Bool>//You can chain this to a series of piped promises
	{
		return RedisLuaTools.initLuaScripts(redis, scripts)
			.then(function(scriptIdsToShas :Map<String, String>) {
				SCRIPT_SHAS = scriptIdsToShas;
				Assert.notNull(SCRIPT_SHAS);
				//This helps with debugging the lua scripts, uses the name instead of the hash
				SCRIPT_SHAS_TOIDS = new Map();
				for (key in SCRIPT_SHAS.keys()) {
					SCRIPT_SHAS_TOIDS[SCRIPT_SHAS[key]] = key;
				}
				return SCRIPT_SHAS != null;
			});
	}

	/**
	 * YOU ONLY WANT TO DO THIS IN A TEST ENVIRONMENT
	 * @param  client :RedisClient  [description]
	 * @return        [description]
	 */
	public static function deleteAllKeys(client :RedisClient) :Promise<Bool>//You can chain this to a series of piped promises
	{
		var deferred = new promhx.deferred.DeferredPromise();
		var commands :Array<Array<String>> = [];

		//Get the prefixed keys
		client.keys(INSTANCE_POOL_PREFIX + '*', function(err, keys :Array<Dynamic>) {
			for (key in keys) {
				commands.push(['del', key]);
			}
			client.multi(commands).exec(function(err, result :Array<Dynamic>) {
				if (err != null) {
					deferred.boundPromise.reject(err);
					return;
				}
				deferred.resolve(true);
			});
		});

		return deferred.boundPromise;
	}

	static function evaluateLuaScript<T>(redis :RedisClient, scriptKey :String, ?args :Array<Dynamic>) :Promise<T>
	{
		return RedisLuaTools.evaluateLuaScript(redis, SCRIPT_SHAS[scriptKey], null, args, SCRIPT_SHAS_TOIDS, scripts);
	}

	/* When we call a Lua script, use the SHA of the already uploaded script for performance */
	static var SCRIPT_SHAS :Map<String, String>;
	static var SCRIPT_SHAS_TOIDS :Map<String, String>;

	inline static var INSTANCE_POOL_PREFIX = 'compute_pool${Constants.SEP}';

	inline public static var REDIS_KEY_WORKER_STATUS = '${INSTANCE_POOL_PREFIX}worker_status';//HASH <MachineId, MachineStatus>
	inline public static var REDIS_KEY_WORKER_STATUS_AVAILABLE = '${INSTANCE_POOL_PREFIX}worker_status_available';//SET <MachineId>
	inline public static var REDIS_KEY_WORKER_AVAILABLE_STATUS = '${INSTANCE_POOL_PREFIX}worker_available_status';//HASH <MachineId, MachineAvailableStatus>
	inline public static var REDIS_KEY_WORKER_AVAILABLE_STATUS_IDLE = '${INSTANCE_POOL_PREFIX}worker_available_status_idle';//SET <MachineId>
	inline public static var REDIS_KEY_WORKER_AVAILABLE_STATUS_WORKING = '${INSTANCE_POOL_PREFIX}worker_available_status_working';//SET <MachineId>
	inline public static var REDIS_KEY_WORKER_AVAILABLE_STATUS_MAXCAPACITY = '${INSTANCE_POOL_PREFIX}worker_available_status_maxcapacity';//SET <MachineId>
	inline public static var REDIS_KEY_WORKER_DEFERRED_TIME = '${INSTANCE_POOL_PREFIX}worker_deferred_time';//SortedSet <MachineId>
	inline public static var REDIS_KEY_WORKER_REMOVED_RECORD = '${INSTANCE_POOL_PREFIX}worker_removed_record';//HASH <MachineId, JsonBlob>

	inline public static var REDIS_KEY_WORKER_STATUS_CHANNEL_PREFIX = '${INSTANCE_POOL_PREFIX}worker_status${Constants.SEP}';//channel
	inline public static var REDIS_KEY_WORKER_AVAILABLE_STATUS_CHANNEL_PREFIX = '${INSTANCE_POOL_PREFIX}worker_available_status${Constants.SEP}';//channel

	inline static var REDIS_KEY_WORKERS = '${INSTANCE_POOL_PREFIX}workers';//HASH <MachineId, MachineDefinition (ssh,docker stuff)>
	public inline static var REDIS_KEY_WORKER_POOLS_PREFIX = '${INSTANCE_POOL_PREFIX}worker_pool${Constants.SEP}';//SortedSet<MachineId>
	public inline static var REDIS_KEY_WORKER_POOLS_SET_PREFIX = '${INSTANCE_POOL_PREFIX}worker_pool_set${Constants.SEP}';//Set<MachineId>
	public inline static var REDIS_KEY_WORKER_POOLS_AVAILABLE_PREFIX = '${INSTANCE_POOL_PREFIX}worker_pool_available${Constants.SEP}';//Set<MachineId>
	public inline static var REDIS_KEY_WORKER_POOLS_CHANNEL_PREFIX = '${REDIS_KEY_WORKER_POOLS_PREFIX}channel${Constants.SEP}';//Key
	inline public static var REDIS_KEY_WORKER_JOBS_PREFIX = '${INSTANCE_POOL_PREFIX}worker_jobs${Constants.SEP}';//Set<ComputeJobId>
	inline public static var REDIS_KEY_POOL_JOBS_PREFIX = '${INSTANCE_POOL_PREFIX}pool_jobs${Constants.SEP}';//Set<ComputeJobId>
	inline static var REDIS_KEY_WORKER_POOL_PRIORITY = '${INSTANCE_POOL_PREFIX}worker_pool_priority';//SortedSet<MachinePoolId>
	inline static var REDIS_KEY_WORKER_POOL_MAX_INSTANCES = '${INSTANCE_POOL_PREFIX}worker_pool_max_instances';//Hash<MachinePoolId, Int>
	inline static var REDIS_KEY_WORKER_POOL_MIN_INSTANCES = '${INSTANCE_POOL_PREFIX}worker_pool_min_instances';//Hash<MachinePoolId, Int>
	inline static var REDIS_KEY_WORKER_POOL_BILLING_INCREMENT = '${INSTANCE_POOL_PREFIX}worker_pool_billing_increment';//Hash<MachinePoolId, Float>
	inline public static var REDIS_KEY_WORKER_POOL_TARGET_INSTANCES = '${INSTANCE_POOL_PREFIX}worker_pool_target_instances';//Key
	inline public static var REDIS_KEY_WORKER_POOL_TARGET_INSTANCES_TOTAL = '${INSTANCE_POOL_PREFIX}worker_pool_target_instances_total';//Key
	inline static var REDIS_KEY_WORKER_POOL_MAP = '${INSTANCE_POOL_PREFIX}worker_pool';//HASH <MachineId, MachinePoolId>
	inline static var REDIS_KEY_WORKER_AVAILABLE_CPUS = '${INSTANCE_POOL_PREFIX}worker_available_cpus';//HASH <MachineId, Int>
	inline static var REDIS_KEY_WORKER_PARAMETERS = '${INSTANCE_POOL_PREFIX}worker_parameters';//HASH <MachineId, InstanceJobParams>
	inline static var REDIS_KEY_WORKER_ADD_TIME = '${INSTANCE_POOL_PREFIX}worker_time_added';//HASH <MachineId, Float>
	//The first machine added to the pool adds the parameters to this set
	//so that scaling requirements can be accurately computed
	inline static var REDIS_KEY_POOL_WORKER_PARAMETERS = '${INSTANCE_POOL_PREFIX}pool_worker_parameters';//HASH <MachinePoolId, InstanceJobParams>
	public inline static var REDIS_KEY_WORKER_JOB_MACHINE_MAP = '${INSTANCE_POOL_PREFIX}job_machine';//HASH <ComputeJobId, MachineId>
	inline static var REDIS_KEY_WORKER_JOB_DEFINITION = '${INSTANCE_POOL_PREFIX}jobs';//HASH <ComputeJobId, JobParams>
	inline public static var REDIS_CHANNEL_KEY_WORKERS_UPDATE = '${INSTANCE_POOL_PREFIX}workers_updated';//channel

	static var KEYS = [
		REDIS_KEY_WORKER_STATUS,
		REDIS_KEY_WORKER_AVAILABLE_STATUS,
		REDIS_KEY_WORKERS,
		REDIS_KEY_WORKER_POOL_PRIORITY,
		REDIS_KEY_WORKER_AVAILABLE_CPUS,
		REDIS_KEY_WORKER_PARAMETERS,
		REDIS_KEY_WORKER_JOB_MACHINE_MAP,
		REDIS_KEY_WORKER_JOB_DEFINITION,
	];

	static var WORKER_HASHES :Map<String, String> = [
		"workers"=>REDIS_KEY_WORKERS,
		"workerPoolMap"=>REDIS_KEY_WORKER_POOL_MAP,
		"cpus"=>REDIS_KEY_WORKER_AVAILABLE_CPUS,
		"workerParameters"=>REDIS_KEY_WORKER_PARAMETERS,
		"status"=>REDIS_KEY_WORKER_STATUS,
		"available_status"=>REDIS_KEY_WORKER_AVAILABLE_STATUS,
		"removed_record"=>REDIS_KEY_WORKER_REMOVED_RECORD,
		"time_added"=>REDIS_KEY_WORKER_ADD_TIME
	];
	static var WORKER_HASHES_STRING_LUA = WORKER_HASHES.keys().array().map(function(k) return k + '="' + WORKER_HASHES[k] + '"').join(", ");

	/**
	 * Redis Lua script Ids.
	 */
	inline static var SCRIPT_ADD_MACHINE = '${INSTANCE_POOL_PREFIX}addmachine';
	inline static var SCRIPT_REMOVE_MACHINE = '${INSTANCE_POOL_PREFIX}removemachine';
	inline static var SCRIPT_MACHINE_FAILED = '${INSTANCE_POOL_PREFIX}machineFailed';
	inline static var SCRIPT_FIND_MACHINE_MATCHING_JOB = '${INSTANCE_POOL_PREFIX}findMachineMatchingJob';
	inline static var SCRIPT_ADD_JOB_TO_MACHINE = '${INSTANCE_POOL_PREFIX}submitJobToMachine';
	inline static var SCRIPT_REMOVE_JOB = '${INSTANCE_POOL_PREFIX}removeJob';
	inline static var SCRIPT_GET_JSON = '${INSTANCE_POOL_PREFIX}getJson';
	inline static var SCRIPT_GET_RAW_JSON = '${INSTANCE_POOL_PREFIX}getRawJson';
	inline static var SCRIPT_GET_WORKERS_IN_POOL = '${INSTANCE_POOL_PREFIX}getWorkersInPool';
	inline static var SCRIPT_REMOVE_WORKERS = '${INSTANCE_POOL_PREFIX}removeWorkers';
	// inline static var SCRIPT_MARK_MACHINE_DOWN = '${INSTANCE_POOL_PREFIX}markMachineDown';
	inline static var SCRIPT_GET_MACHINE_FOR_JOB = '${INSTANCE_POOL_PREFIX}getMachineForJob';
	inline static var SCRIPT_SET_TOTAL_WORKER_COUNT = '${INSTANCE_POOL_PREFIX}setTotalWorkerCount';
	inline static var SCRIPT_UPDATE_TOTAL_WORKER_COUNT = '${INSTANCE_POOL_PREFIX}updateTotalWorkerCount';
	inline static var SCRIPT_SET_WORKER_DEFERRED_TIMEOUT = '${INSTANCE_POOL_PREFIX}setWorkerDeferredTimeout';
	inline static var SCRIPT_SET_WORKER_STATUS = '${INSTANCE_POOL_PREFIX}setWorkerStatus';
	inline static var SCRIPT_SET_WORKER_STATUS_DEFFERED_TO_REMOVING = '${INSTANCE_POOL_PREFIX}setWorkerStatusDeferredToRemoving';
	inline static var SCRIPT_GET_ALL_WORKER_TIMEOUTS = '${INSTANCE_POOL_PREFIX}getAllWorkerTimeouts';


	//Expects machineId, status
	inline public static var SNIPPET_UPDATE_MACHINE_STATUS =
'
	redis.call("HSET", "$REDIS_KEY_WORKER_STATUS", machineId, status)
	if status == "${MachineStatus.Available}" then
		redis.call("SADD", "$REDIS_KEY_WORKER_STATUS_AVAILABLE", machineId)
	else
		redis.call("SREM", "$REDIS_KEY_WORKER_STATUS_AVAILABLE", machineId)

	end
	if status ~= "${MachineStatus.Deferred}" then
		redis.call("ZREM", "$REDIS_KEY_WORKER_DEFERRED_TIME", machineId)
	end
	--print("publishing to $REDIS_KEY_WORKER_STATUS_CHANNEL_PREFIX" .. machineId .. "   status=" .. status)
	redis.call("PUBLISH", "$REDIS_KEY_WORKER_STATUS_CHANNEL_PREFIX" .. machineId, status)
';

	inline public static var SNIPPET_UPDATE_MACHINE_AVAILABLE_STATUS =
'
	redis.call("HSET", "$REDIS_KEY_WORKER_AVAILABLE_STATUS", machineId, availableStatus)
	if availableStatus == "${MachineAvailableStatus.Idle}" then
		redis.call("SADD", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_IDLE", machineId)
		redis.call("SREM", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_WORKING", machineId)
		redis.call("SREM", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_MAXCAPACITY", machineId)
	elseif availableStatus == "${MachineAvailableStatus.Working}" then
		redis.call("SREM", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_IDLE", machineId)
		redis.call("SADD", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_WORKING", machineId)
		redis.call("SREM", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_MAXCAPACITY", machineId)
	elseif availableStatus == "${MachineAvailableStatus.MaxCapacity}" then
		redis.call("SREM", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_IDLE", machineId)
		redis.call("SREM", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_WORKING", machineId)
		redis.call("SADD", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_MAXCAPACITY", machineId)
	end
	redis.call("PUBLISH", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_CHANNEL_PREFIX" .. machineId, availableStatus)
';

	inline public static var SNIPPET_UPDATE_MACHINE_CHANNEL =
'
	redis.call("PUBLISH", "$REDIS_CHANNEL_KEY_WORKERS_UPDATE", "update")
';

	inline public static var SNIPPET_FIND_MACHINE_FOR_JOB =
'
--Go through all the machine pools and the subsequent machines
local machinePoolKeys = redis.call("ZRANGE", "$REDIS_KEY_WORKER_POOL_PRIORITY", 0, -1)
local foundMachineId = false
for index,poolId in ipairs(machinePoolKeys) do
	if foundMachineId then
		break
	end
	local pool = "$REDIS_KEY_WORKER_POOLS_PREFIX" .. poolId
	local machines = redis.call("ZRANGE", pool, 0, -1)
	for index,machineId in ipairs(machines) do
		local status = redis.call("HGET", "$REDIS_KEY_WORKER_STATUS", machineId)
		local availableCPUs = tonumber(redis.call("HGET", "$REDIS_KEY_WORKER_AVAILABLE_CPUS", machineId))
		--Later we can add more logic here e.g. matching jobs to upstream job machines
		if jobParameters.cpus <= availableCPUs and status == "${MachineStatus.Available}" then
			foundMachineId = machineId
			break
		end
	end
end
local machineId = foundMachineId
';

	inline public static var SNIPPET_ADD_JOB_TO_MACHINE =
'
--Variables expected: computeJobId, jobParameters, machineId, time
--Update the machine status,cpus,etc and add the job records

local availableStatus = redis.call("HGET", "$REDIS_KEY_WORKER_AVAILABLE_STATUS", machineId)

local availableCPUs = tonumber(redis.call("HGET", "$REDIS_KEY_WORKER_AVAILABLE_CPUS", machineId))
--Reduce the CPUS
local remainingCpus = availableCPUs - jobParameters.cpus
redis.call("HSET", "$REDIS_KEY_WORKER_AVAILABLE_CPUS", machineId, remainingCpus)
--Update the machine status
if remainingCpus <= 0 then
	availableStatus = "${MachineAvailableStatus.MaxCapacity}"
else
	availableStatus = "${MachineAvailableStatus.Working}"
end
--Add the job to the machine set
redis.call("SADD", "$REDIS_KEY_WORKER_JOBS_PREFIX" .. machineId, computeJobId)
--Map the job to the machine
redis.call("HSET", "$REDIS_KEY_WORKER_JOB_MACHINE_MAP", computeJobId, machineId)
--Save the job definition
redis.call("HSET", "$REDIS_KEY_WORKER_JOB_DEFINITION", computeJobId, cjson.encode(jobParameters))

--Notify the pool channel so it can respond
local poolId = redis.call("HGET", "$REDIS_KEY_WORKER_POOL_MAP", machineId)
--Add the job to the pool set
redis.call("SADD", "$REDIS_KEY_POOL_JOBS_PREFIX" .. poolId, computeJobId)

$SNIPPET_UPDATE_MACHINE_AVAILABLE_STATUS

local channel = "$REDIS_KEY_WORKER_JOBS_PREFIX" .. machineId
local allJobsInMachine = redis.call("SMEMBERS", "$REDIS_KEY_WORKER_JOBS_PREFIX" .. machineId)
redis.call("PUBLISH", channel, "update")

';

	inline public static var SNIPPET_GET_MACHINE_FOR_JOB =
'
local machineId = redis.call("HGET", "${REDIS_KEY_WORKER_JOB_MACHINE_MAP}", computeJobId)
local machineDef = redis.call("HGET", "${REDIS_KEY_WORKERS}", machineId)
';

	inline public static var SNIPPET_REMOVE_COMPUTE_JOB_DATA =
'
--Remove the job from the machine set
local channel = "$REDIS_KEY_WORKER_JOBS_PREFIX" .. machineId
redis.call("SREM", channel, computeJobId)

--Remove the job->machine key
redis.call("HDEL", "$REDIS_KEY_WORKER_JOB_MACHINE_MAP", computeJobId)

--Remove the job definition
redis.call("HDEL", "$REDIS_KEY_WORKER_JOB_DEFINITION", computeJobId)

--Remove the job from the pool set
local poolId = redis.call("HGET", "$REDIS_KEY_WORKER_POOL_MAP", machineId)
redis.call("SREM", "$REDIS_KEY_POOL_JOBS_PREFIX" .. poolId, computeJobId)

--Notify the jobs manager
redis.call("PUBLISH", channel, "update")
';

	inline public static var SNIPPET_REMOVE_JOB =
//Expects computeJobId
'
local machineId = redis.call("HGET", "$REDIS_KEY_WORKER_JOB_MACHINE_MAP", computeJobId)
if not machineId then
	return {err="Job " .. computeJobId .. " does not exist"}
end
local job = cjson.decode(redis.call("HGET", "$REDIS_KEY_WORKER_JOB_DEFINITION", computeJobId))

--Add the cpus back to the machine
local currentMachineCPUs = tonumber(redis.call("HGET", "$REDIS_KEY_WORKER_AVAILABLE_CPUS", machineId))
currentMachineCPUs = currentMachineCPUs + job.cpus
redis.call("HSET", "$REDIS_KEY_WORKER_AVAILABLE_CPUS", machineId, currentMachineCPUs)

--Update the worker status. This might be merged with the above soon
local availableStatus = redis.call("HGET", "$REDIS_KEY_WORKER_AVAILABLE_STATUS", machineId)
local parameters = cjson.decode(redis.call("HGET", "$REDIS_KEY_WORKER_PARAMETERS", machineId))
if parameters.cpus == currentMachineCPUs then
	availableStatus = "${MachineAvailableStatus.Idle}"
else
	availableStatus = "${MachineAvailableStatus.Working}"
end

$SNIPPET_REMOVE_COMPUTE_JOB_DATA

local status = redis.call("HGET", "$REDIS_KEY_WORKER_STATUS", machineId)
if not (status == "${MachineStatus.Removing}" or status == "${MachineStatus.Failed}") then
	if status == "${MachineStatus.WaitingForRemoval}" and redis.call("SCARD", "$REDIS_KEY_WORKER_JOBS_PREFIX"  .. machineId) == 0 then
		print("worker has no jobs and marked for removal, setting machine to be removed")
		status = "${MachineStatus.Deferred}"
	end
	$SNIPPET_UPDATE_MACHINE_AVAILABLE_STATUS
	$SNIPPET_UPDATE_MACHINE_STATUS
end
';

	inline public static var SNIPPET_UPDATE_WORKER_COUNTS =
//Expects targetWorkerCount:Int
'
local machinePoolKeys = redis.call("ZRANGE", "$REDIS_KEY_WORKER_POOL_PRIORITY", 0, -1)
local currentWorkerCount = 0
local currentWorkers = {}
local totalMinWorkers = 0
local targetWorkers = {}
for index,poolId in ipairs(machinePoolKeys) do
	local pool = "$REDIS_KEY_WORKER_POOLS_PREFIX" .. poolId
	local currentWorkersInPool = redis.call("SINTER", "$REDIS_KEY_WORKER_STATUS_AVAILABLE", "$REDIS_KEY_WORKER_POOLS_SET_PREFIX" .. poolId)
	currentWorkers[poolId] = #currentWorkersInPool
	currentWorkerCount = currentWorkerCount + currentWorkers[poolId]
	targetWorkers[poolId] = currentWorkers[poolId]
	local minWorkerCount = tonumber(redis.call("HGET", "$REDIS_KEY_WORKER_POOL_MIN_INSTANCES", poolId)) or 0
	totalMinWorkers = totalMinWorkers + minWorkerCount
end

targetWorkerCount = math.max(targetWorkerCount, totalMinWorkers)

if currentWorkerCount > targetWorkerCount then
	local machinesToShutdown = currentWorkerCount - targetWorkerCount
	--Go backwards through the pools in reverse priority
	local i = #machinePoolKeys
	while machinesToShutdown > 0 and i > 0 do
		local poolId = machinePoolKeys[i]
		local pool = "$REDIS_KEY_WORKER_POOLS_PREFIX" .. poolId
		local readyWorkers = redis.call("SINTER", "$REDIS_KEY_WORKER_STATUS_AVAILABLE", "$REDIS_KEY_WORKER_POOLS_SET_PREFIX" .. poolId)
		local minWorkerCount = tonumber(redis.call("HGET", "$REDIS_KEY_WORKER_POOL_MIN_INSTANCES", poolId)) or 0

		local poolMachinesAvailableToCut = math.max(#readyWorkers - minWorkerCount, 0)
		local poolMachinesToCut = math.min(poolMachinesAvailableToCut, machinesToShutdown)
		if poolMachinesToCut > 0 then
			targetWorkers[poolId] = #readyWorkers - poolMachinesToCut
			for i=1, poolMachinesToCut do
				local status = "${MachineStatus.WaitingForRemoval}"
				local machineId = readyWorkers[i]
				if redis.call("SCARD", "$REDIS_KEY_WORKER_JOBS_PREFIX"  .. machineId) == 0 then
					status = "${MachineStatus.Deferred}"
				end
				$SNIPPET_UPDATE_MACHINE_STATUS
			end
		end
		i = i - 1
	end
elseif currentWorkerCount < targetWorkerCount then
	local machinesToCreate = targetWorkerCount - currentWorkerCount
	local i = 1
	while machinesToCreate > 0 and i <= #machinePoolKeys do
		--Go forwards through the pools in normal priority
		local poolId = machinePoolKeys[i]
		local pool = "$REDIS_KEY_WORKER_POOLS_PREFIX" .. poolId
		local machines = redis.call("ZRANGE", pool, 0, -1)
		local readyWorkers = {}
		for index,machineId in ipairs(machines) do
			local status = redis.call("HGET", "$REDIS_KEY_WORKER_STATUS", machineId)
			if status == "${MachineStatus.Available}" then
				table.insert(readyWorkers, machineId)
			end
		end
		local workerCount = #readyWorkers

		local maxWorkerCount = tonumber(redis.call("HGET", "$REDIS_KEY_WORKER_POOL_MAX_INSTANCES", poolId))
		if workerCount < maxWorkerCount then
			local maxPotentialWorkers = maxWorkerCount - workerCount
			if machinesToCreate >= maxPotentialWorkers then
				machinesToCreate = machinesToCreate - maxPotentialWorkers
				targetWorkers[poolId] = workerCount + maxPotentialWorkers
			else
				targetWorkers[poolId] = workerCount + machinesToCreate
				machinesToCreate = 0
			end
		end
		i = i + 1
	end
end

local totalDifference = 0
for index,poolId in ipairs(machinePoolKeys) do
	totalDifference = totalDifference + (targetWorkers[poolId] - currentWorkers[poolId])
end

local result = cjson.encode(targetWorkers)
redis.call("SET", "$REDIS_KEY_WORKER_POOL_TARGET_INSTANCES", result)
redis.call("PUBLISH", "$REDIS_KEY_WORKER_POOL_TARGET_INSTANCES", result)
$SNIPPET_UPDATE_MACHINE_CHANNEL
';


	inline public static var SNIPPET_SCALE_WORKERS_UP =
	//Expects required = {cpus=10}
'
if not required then
	print("Missing required object")
	return
end
if not required.cpus or required.cpus == 0 then
	print("Zero new requirements")
else
	local cpusRemaining = required.cpus
	local machinePoolKeys = redis.call("ZRANGE", "$REDIS_KEY_WORKER_POOL_PRIORITY", 0, -1)
	local machinesAdded = 0
	for index,poolId in ipairs(machinePoolKeys) do
		if cpusRemaining <= 0 then
			break
		end
		local workerParameters = redis.call("HGET", "$REDIS_KEY_POOL_WORKER_PARAMETERS", poolId)
		if not workerParameters then
			--No worker has been added, we have no idea what the worker machines look like
			workerParameters = {cpus=1}
		else
			workerParameters = cjson.decode(workerParameters)
		end
		local wantedNewWorkers = math.max(math.ceil(cpusRemaining / workerParameters.cpus), 1)
		local maxWorkers = tonumber(redis.call("HGET", "$REDIS_KEY_WORKER_POOL_MAX_INSTANCES", poolId))
		local currentWorkers = redis.call("SINTER", "$REDIS_KEY_WORKER_STATUS_AVAILABLE", "$REDIS_KEY_WORKER_POOLS_SET_PREFIX" .. poolId)
		local availableCapacity = maxWorkers - #currentWorkers
		local newWorkers = math.min(wantedNewWorkers, availableCapacity)
		machinesAdded = machinesAdded + newWorkers
		cpusRemaining = math.max(cpusRemaining - (newWorkers * workerParameters.cpus), 0)
	end
	if machinesAdded > 0 then
		local targetWorkerCount = tonumber(redis.call("GET", "$REDIS_KEY_WORKER_POOL_TARGET_INSTANCES_TOTAL"))
		print("current targetWorkerCount=" .. tostring(targetWorkerCount))
		if not targetWorkerCount then
			targetWorkerCount = 0
		end
		targetWorkerCount = redis.call("SCARD", "$REDIS_KEY_WORKER_STATUS_AVAILABLE") + machinesAdded
		redis.call("SET", "$REDIS_KEY_WORKER_POOL_TARGET_INSTANCES_TOTAL", targetWorkerCount)
		$SNIPPET_UPDATE_WORKER_COUNTS
	end
end

';

inline public static var SNIPPET_SCALE_WORKERS_DOWN_NO =
	//Counts idle machines and reduces the target machines by that amount
'
local targetWorkerCount = 0
redis.call("SET", "$REDIS_KEY_WORKER_POOL_TARGET_INSTANCES_TOTAL", 0)
$SNIPPET_UPDATE_WORKER_COUNTS
return
';

inline public static var SNIPPET_SCALE_WORKERS_DOWN =
	//Counts idle machines and reduces the target machines by that amount
'
--Go through all the machine pools and the subsequent machines
--Count idle machines, and reduce the target machine count by that amount
local machinePoolKeys = redis.call("ZRANGE", "$REDIS_KEY_WORKER_POOL_PRIORITY", 0, -1)
local machinesRemoved = 0
local targetWorkerCount = 0
for index,poolId in ipairs(machinePoolKeys) do
	local machines = redis.call("SINTER", "$REDIS_KEY_WORKER_STATUS_AVAILABLE", "$REDIS_KEY_WORKER_POOLS_SET_PREFIX" .. poolId)
	local minMachines = tonumber(redis.call("HGET", "$REDIS_KEY_WORKER_POOL_MIN_INSTANCES", poolId)) or 0
	local allowedToRemove = math.max(#machines - minMachines, 0)
	if allowedToRemove > 0 then
		for index,machineId in ipairs(machines) do
			local workerJobCount = redis.call("SCARD", "$REDIS_KEY_WORKER_JOBS_PREFIX" .. machineId)
			local workerStatus = redis.call("HGET", "$REDIS_KEY_WORKER_STATUS", machineId)
			if allowedToRemove > 0 and workerJobCount == 0 and redis.call("HGET", "$REDIS_KEY_WORKER_STATUS", machineId) == "${MachineStatus.Available}" then
				machinesRemoved = machinesRemoved + 1
				allowedToRemove = allowedToRemove - 1
			end
		end
	end
end
local targetWorkerCount = redis.call("SCARD", "$REDIS_KEY_WORKER_STATUS_AVAILABLE") - machinesRemoved
redis.call("SET", "$REDIS_KEY_WORKER_POOL_TARGET_INSTANCES_TOTAL", targetWorkerCount)
$SNIPPET_UPDATE_WORKER_COUNTS
';

	static var SNIPPET_REMOVE_WORKER =
'
local poolId = redis.call("HGET", "$REDIS_KEY_WORKER_POOL_MAP", machineId)
if poolId == nil or type(poolId) == "boolean" then
	return {err="Cannot remove worker=" .. machineId .. ", no matching poolId. This is bad. poolId=" .. tostring(poolId)}
end

--Create and set the worker record so that we never forget when and how this was terminated
local removedRecord = {poolId=poolId, id=machineId}
removedRecord["parameters"] = cjson.decode(redis.call("HGET", "$REDIS_KEY_WORKER_PARAMETERS", machineId))
removedRecord["time_removal"] = time
removedRecord["time_added"] = tonumber(redis.call("HGET", "$REDIS_KEY_WORKER_ADD_TIME", machineId))

removedRecord["time_deferred"] = redis.call("ZSCORE", "$REDIS_KEY_WORKER_DEFERRED_TIME", machineId)
redis.call("HSET", "$REDIS_KEY_WORKER_REMOVED_RECORD", machineId, cjson.encode(removedRecord))

for k,v in pairs({${WORKER_HASHES.map(function(s) return '\"' + s + '\"').array().join(", ")}}) do
	if v ~= "$REDIS_KEY_WORKER_REMOVED_RECORD" then
		redis.call("HDEL", v, machineId)
	end
end
redis.call("ZREM", "$REDIS_KEY_WORKER_POOLS_PREFIX" .. poolId, machineId)
redis.call("SREM", "$REDIS_KEY_WORKER_POOLS_SET_PREFIX" .. poolId, machineId)
redis.call("SREM", "$REDIS_KEY_WORKER_STATUS_AVAILABLE", machineId)
redis.call("SREM", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_IDLE", machineId)
redis.call("SREM", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_WORKING", machineId)
redis.call("SREM", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_MAXCAPACITY", machineId)
redis.call("ZREM", "$REDIS_KEY_WORKER_DEFERRED_TIME", machineId)

';

public static var SNIPPET_GET_JSON =
'
local machinePoolKeys = redis.call("ZRANGE", "$REDIS_KEY_WORKER_POOL_PRIORITY", 0, -1)
local result = {pools={}}
for index,poolId in ipairs(machinePoolKeys) do
	local pool = "$REDIS_KEY_WORKER_POOLS_PREFIX" .. poolId
	local instanceList = {}
	local poolScore = redis.call("ZSCORE", "$REDIS_KEY_WORKER_POOL_PRIORITY", poolId)
	--local poolEntry = {id=poolId, score=tonumber(poolScore), instances=instanceList}
	local poolEntry = {id=poolId, score=tonumber(poolScore)}
	table.insert(result.pools, poolEntry)
	local machines = redis.call("ZRANGE", pool, 0, -1)
	for index,machineId in ipairs(machines) do
		local jobs = {}
		local machineDescription = {id=machineId}
		table.insert(instanceList, machineDescription)
		local jobIds = redis.call("SMEMBERS", "$REDIS_KEY_WORKER_JOBS_PREFIX" .. machineId)
		for index,jobId in ipairs(jobIds) do
			table.insert(jobs, jobId)
		end
		if #jobs > 0 then
			machineDescription.jobs = jobs
		end
		local cpus = tonumber(redis.call("HGET", "$REDIS_KEY_WORKER_AVAILABLE_CPUS", machineId))
		machineDescription.cpus = cpus
	end
	if #instanceList > 0 then
		poolEntry.instances = instanceList
	end
end
for hashkey,rediskey in pairs({${WORKER_HASHES.keys().array().map(function(k) return k + '=\"' + WORKER_HASHES[k] + '\"').join(", ")}}) do
	local t = {}
	local all = redis.call("HGETALL", rediskey)
	if all then
		for i=1,#all, 2 do
			if hashkey == "cpus" then
				t[all[i]] = tonumber(all[i+1])
			elseif hashkey == "workers" or hashkey == "workerParameters" or hashkey == "removed_record" then
				local workerDef = cjson.decode(all[i+1])
				--Remove the key text because it is useless when inspecting
				if workerDef.ssh then
					workerDef.ssh.privateKey = nil
				end
				if workerDef.docker then
					workerDef.docker.key = nil
				end
				t[all[i]] = workerDef
			else
				t[all[i]] = all[i+1]
			end
		end
	end
	result[hashkey] = t
end

local jobs = {}
local all = redis.call("HGETALL", "$REDIS_KEY_WORKER_JOB_MACHINE_MAP")
for i=1,#all, 2 do
	jobs[all[i]] = all[i+1]
end
result.jobs = jobs

local maxInstances = {}
local all = redis.call("HGETALL", "$REDIS_KEY_WORKER_POOL_MAX_INSTANCES")
for i=1,#all, 2 do
	maxInstances[all[i]] = tonumber(all[i+1])
end
result.maxInstances = maxInstances

local minInstances = {}
local all = redis.call("HGETALL", "$REDIS_KEY_WORKER_POOL_MIN_INSTANCES")
for i=1,#all, 2 do
	minInstances[all[i]] = tonumber(all[i+1])
end
result.minInstances = minInstances

local defaultWorkerParameters = {}
local all = redis.call("HGETALL", "$REDIS_KEY_POOL_WORKER_PARAMETERS")
for i=1,#all, 2 do
	defaultWorkerParameters[all[i]] = cjson.decode(all[i+1])
end
result.defaultWorkerParameters = defaultWorkerParameters

local targetInstancesString = redis.call("GET", "$REDIS_KEY_WORKER_POOL_TARGET_INSTANCES")
if targetInstancesString then
	result.targetWorkers = cjson.decode(targetInstancesString)
else
	result.targetWorkers = {}
end

result.totalTargetInstances = tonumber(redis.call("GET", "$REDIS_KEY_WORKER_POOL_TARGET_INSTANCES_TOTAL")) or 0

result.available = redis.call("SMEMBERS", "$REDIS_KEY_WORKER_STATUS_AVAILABLE")

local workerStatus = {}
local all = redis.call("HGETALL", "$REDIS_KEY_WORKER_STATUS")
for i=1,#all, 2 do
	workerStatus[all[i]] = all[i+1]
end
result.status = workerStatus

local workerTimeouts = {}
local all = redis.call("HGETALL", "$REDIS_KEY_WORKER_STATUS")
for i=1,#all, 2 do
	local machineId = all[i]
	local timeout = tonumber(redis.call("ZSCORE", "$REDIS_KEY_WORKER_DEFERRED_TIME", machineId))
	workerTimeouts[machineId] = timeout
end
result.timeouts = workerTimeouts

';

/* The literal Redis Lua scripts. These allow non-race condition and performant operations on the DB*/
	static var scripts :Map<String, String> = [
			SCRIPT_ADD_MACHINE =>
'
local poolId = ARGV[1]
local workerString = ARGV[2]
local workerDefinition = cjson.decode(workerString)
local machineId = workerDefinition.id

local status = ARGV[4]
local time = tonumber(ARGV[5])

if not status then
	status = "${MachineStatus.Available}"
end

local availableStatus = "${MachineAvailableStatus.Idle}"

if redis.call("HGET", "$REDIS_KEY_WORKER_STATUS", machineId) ~= "${MachineStatus.Initializing}" and redis.call("HEXISTS", "$REDIS_KEY_WORKERS", machineId) ~= 0 then
	print("Adding machine but it already exists=" .. machineId)
	$SNIPPET_UPDATE_MACHINE_STATUS
	return
end

local workerParametersString = ARGV[3]
local workerParameters = cjson.decode(workerParametersString)

if not workerParameters.cpus then
	return {err="Cannot add worker, missing cpus field in parameters "}
end

--Override the pool worker parameters
redis.call("HSET", "$REDIS_KEY_POOL_WORKER_PARAMETERS", poolId, workerParametersString)

--If there is no priority for the pool, set one
if not redis.call("ZRANK", "$REDIS_KEY_WORKER_POOL_PRIORITY", poolId) then
	print("Missing poolId in priority set, adding " .. tostring(poolId) .. "=1")
	redis.call("ZADD", "$REDIS_KEY_WORKER_POOL_PRIORITY", $DEFAULT_COMPUTE_POOL_SCORE, poolId)
end

--Add the instance definition to the hashes
redis.call("HSET", "$REDIS_KEY_WORKERS", machineId, workerString)
redis.call("HSET", "$REDIS_KEY_WORKER_STATUS", machineId, status)
redis.call("HSET", "$REDIS_KEY_WORKER_AVAILABLE_STATUS", machineId, availableStatus)
redis.call("HSET", "$REDIS_KEY_WORKER_POOL_MAP", machineId, poolId)
redis.call("HSET", "$REDIS_KEY_WORKER_PARAMETERS", machineId, workerParametersString)
redis.call("HSET", "$REDIS_KEY_WORKER_ADD_TIME", machineId, time)


--Set all the parameters. For the moment just set the cpus
redis.call("HSET", "$REDIS_KEY_WORKER_AVAILABLE_CPUS", machineId, workerParameters.cpus)

local pool = "$REDIS_KEY_WORKER_POOLS_PREFIX" .. poolId

--Make sure this instance is the last in the set
local lastInSet = redis.call("ZRANGE", pool, -1, -1)[1]
local score = 1
if lastInSet then
	score = redis.call("ZSCORE", pool, lastInSet)
end
score = score + 1

--Add the machine to the pool
redis.call("ZADD", pool, score, machineId)
redis.call("SADD", "$REDIS_KEY_WORKER_POOLS_SET_PREFIX" .. poolId, machineId)

$SNIPPET_UPDATE_MACHINE_STATUS
$SNIPPET_UPDATE_MACHINE_AVAILABLE_STATUS

${ComputeQueue.SNIPPET_PROCESS_PENDING}

$SNIPPET_UPDATE_MACHINE_CHANNEL

',
			SCRIPT_REMOVE_MACHINE =>
'
local machineId = ARGV[1]

-- if redis.call("HEXISTS", "$ REDIS_KEY_WORKERS", machineId) == 0 then
-- 	print("Cannot remove worker, does not exist id=" .. machineId)
--	return
-- end

local worker = redis.call("HGET", "$REDIS_KEY_WORKERS", machineId)
local time = tonumber(ARGV[2]) --Do not need this right now, but want to log

local machineJobsKey = "$REDIS_KEY_WORKER_JOBS_PREFIX" .. machineId
local jobCount = tonumber(redis.call("SCARD", machineJobsKey))
if jobCount > 0 then
	return {err="Cannot remove worker=" .. machineId .. ", " .. tostring(jobCount) .. " jobs still remaining"}
end

$SNIPPET_REMOVE_WORKER

$SNIPPET_UPDATE_MACHINE_CHANNEL

return worker
',

			SCRIPT_MACHINE_FAILED =>
'
local machineId = ARGV[1]
local time = tonumber(ARGV[2])

if redis.call("HEXISTS", "$REDIS_KEY_WORKERS", machineId) == 0 then
	print("Cannot remove worker, does not exist id=" .. machineId)
	return
end

local status = redis.call("HGET", "$REDIS_KEY_WORKER_STATUS", machineId)

--Idempotent
if status == "${MachineStatus.Failed}" then
	return
end
--Already removing
if status == "${MachineStatus.Removing}" then
	return
end
--Now set the status
status = "${MachineStatus.Removing}"
$SNIPPET_UPDATE_MACHINE_STATUS

local worker = redis.call("HGET", "$REDIS_KEY_WORKERS", machineId)
local poolId = redis.call("HGET", "$REDIS_KEY_WORKER_POOL_MAP", machineId)

local computeJobIds = redis.call("SMEMBERS", "$REDIS_KEY_WORKER_JOBS_PREFIX" .. machineId)
for index,computeJobId in ipairs(computeJobIds) do
	print("Requeuing " .. tostring(computeJobId))
	${ComputeQueue.SNIPPET_REQUEUE_COMPUTE_JOB}
end

--$ SNIPPET_REMOVE_WORKER

${ComputeQueue.SNIPPET_PROCESS_PENDING}

$SNIPPET_UPDATE_MACHINE_CHANNEL
',

			SCRIPT_FIND_MACHINE_MATCHING_JOB =>
'
local jobParamsString = ARGV[1] --JobParams
local jobParameters = cjson.decode(jobParamsString) --JobParams

$SNIPPET_FIND_MACHINE_FOR_JOB


return machineId
',
			SCRIPT_ADD_JOB_TO_MACHINE =>
'
local computeJobId = ARGV[1]
local jobParamsString = ARGV[2] --JobParams
local jobParameters = cjson.decode(jobParamsString) --JobParams

if not jobParameters.cpus then
	jobParameters.cpus = 1
end
local machineId = ARGV[3]
local time = tonumber(ARGV[4])

$SNIPPET_ADD_JOB_TO_MACHINE

',

			SCRIPT_GET_MACHINE_FOR_JOB =>
'
local computeJobId = ARGV[1]
$SNIPPET_GET_MACHINE_FOR_JOB
return machineDef
',

			SCRIPT_REMOVE_JOB =>
'
local computeJobId = ARGV[1]
$SNIPPET_REMOVE_JOB
',
			SCRIPT_GET_JSON =>
'
$SNIPPET_GET_JSON
return cjson.encode(result)
',


			SCRIPT_GET_RAW_JSON =>
'
local hashes = {"$REDIS_KEY_WORKER_STATUS", "$REDIS_KEY_WORKER_AVAILABLE_STATUS", "$REDIS_KEY_WORKERS", "$REDIS_KEY_WORKER_POOL_MAX_INSTANCES", "$REDIS_KEY_WORKER_POOL_MIN_INSTANCES", "$REDIS_KEY_WORKER_POOL_BILLING_INCREMENT", "$REDIS_KEY_WORKER_POOL_MAP", "$REDIS_KEY_WORKER_AVAILABLE_CPUS", "$REDIS_KEY_WORKER_PARAMETERS", "$REDIS_KEY_POOL_WORKER_PARAMETERS", "$REDIS_KEY_WORKER_JOB_MACHINE_MAP", "$REDIS_KEY_WORKER_JOB_DEFINITION"}
local sets = {"$REDIS_KEY_WORKER_STATUS_AVAILABLE", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_IDLE", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_WORKING", "$REDIS_KEY_WORKER_AVAILABLE_STATUS_MAXCAPACITY", "$REDIS_KEY_WORKER_POOLS_AVAILABLE_PREFIX"}
local sortedSets = {"$REDIS_KEY_WORKER_DEFERRED_TIME", "$REDIS_KEY_WORKER_POOL_PRIORITY"}
local sortedSetPrefixes = {}
local setKeyPrefixes = {"$REDIS_KEY_WORKER_JOBS_PREFIX", "$REDIS_KEY_POOL_JOBS_PREFIX", "$REDIS_KEY_WORKER_POOLS_SET_PREFIX"}--, "$REDIS_KEY_WORKER_POOLS_PREFIX"}

local result = {}

for i,hashKey in ipairs(hashes) do
	local all = redis.call("HGETALL", hashKey)
	result[hashKey] = {}
	for i=1,#all, 2 do
		result[hashKey][all[i]] = all[i+1]
	end
end

for i,setKey in ipairs(sets) do
	result[setKey] = redis.call("SMEMBERS", setKey)
end

for i,setPrefix in ipairs(setKeyPrefixes) do
	local keys = redis.call("KEYS", setPrefix .. "*")
	for j,setKey in ipairs(keys) do
		result[setKey] = redis.call("SMEMBERS", setKey)
	end
end

for i,sortedSetKey in ipairs(sortedSets) do
	local sortedKeyTable = redis.call("ZRANGE", sortedSetKey, 0, -1)
	result[sortedSetKey] = {}
	for index,key in ipairs(sortedKeyTable) do
		result[sortedSetKey][index] = key
	end
end

for i,sortedSetPrefix in ipairs(sortedSetPrefixes) do
	local keys = redis.call("KEYS", sortedSetPrefix .. "*")
	for j,sortedSetKey in ipairs(keys) do
		local sortedKeyTable = redis.call("ZRANGE", sortedSetKey, 0, -1)
		result[sortedSetKey] = {}
		for index,key in ipairs(sortedKeyTable) do
			result[sortedSetKey][index] = key
		end
	end
end

return cjson.encode(result)
',


			SCRIPT_GET_WORKERS_IN_POOL =>
'
local poolId = ARGV[1]
local pool = "$REDIS_KEY_WORKER_POOLS_PREFIX" .. poolId
local result = {}
local machines = redis.call("ZRANGE", pool, 0, -1)
for index,machineId in ipairs(machines) do
	local status = redis.call("HGET", "$REDIS_KEY_WORKER_STATUS", machineId)
	local availableStatus = redis.call("HGET", "$REDIS_KEY_WORKER_AVAILABLE_STATUS", machineId)
	table.insert(result, {id=machineId,status=status,availableStatus=availableStatus})
end
return cjson.encode(result)
',

/**
 * Return all machines that are marked for removal and have no jobs
 * and set their status to 'Deferred'. These can then be actually
 * safely removed by the cloud infrastructure.
 *
 * They can also be kept around, e.g. for Amazon hourly billing cycle
 * but that is up to the cloud implementation.
 */
			SCRIPT_REMOVE_WORKERS =>
'
local poolId = ARGV[1]
local pool = "$REDIS_KEY_WORKER_POOLS_PREFIX" .. poolId

local result = {}

local machines = redis.call("ZRANGE", pool, 0, -1)
for index,machineId in ipairs(machines) do
	local status = redis.call("HGET", "$REDIS_KEY_WORKER_STATUS", machineId)
	if status == "${MachineStatus.WaitingForRemoval}" then
		local machineJobsKey = "$REDIS_KEY_WORKER_JOBS_PREFIX" .. machineId
		local jobCount = redis.call("SCARD", machineJobsKey)
		if jobCount == 0 then
			table.insert(result, machineId)
			status = "${MachineStatus.Deferred}"
			$SNIPPET_UPDATE_MACHINE_STATUS
		end
	end
end

$SNIPPET_UPDATE_MACHINE_CHANNEL

return cjson.encode(result)
',

/**
 * Update the total workers for each pool
 */
			SCRIPT_SET_TOTAL_WORKER_COUNT =>
'
local targetWorkerCount = tonumber(ARGV[1])
print("SCRIPT_SET_TOTAL_WORKER_COUNT targetWorkerCount=" .. tostring(targetWorkerCount))
redis.call("SET", "$REDIS_KEY_WORKER_POOL_TARGET_INSTANCES_TOTAL", targetWorkerCount)
$SNIPPET_UPDATE_WORKER_COUNTS
print(cjson.encode({current=currentWorkers, target=targetWorkers, totalDifference=totalDifference}))

$SNIPPET_GET_JSON
print("json=" .. cjson.encode(result))

return cjson.encode({current=currentWorkers, target=targetWorkers, totalDifference=totalDifference})

',

			SCRIPT_UPDATE_TOTAL_WORKER_COUNT =>
'
local targetWorkerCount = tonumber(redis.call("GET", "$REDIS_KEY_WORKER_POOL_TARGET_INSTANCES_TOTAL")) or 0
$SNIPPET_UPDATE_WORKER_COUNTS
',

			SCRIPT_SET_WORKER_DEFERRED_TIMEOUT =>
'
local machineId = ARGV[1]
local time = tonumber(ARGV[2])
local status = "${MachineStatus.Deferred}"
redis.call("ZADD", "$REDIS_KEY_WORKER_DEFERRED_TIME", time, machineId)
$SNIPPET_UPDATE_MACHINE_STATUS
',

			SCRIPT_SET_WORKER_STATUS =>
'
local machineId = ARGV[1]
local status = ARGV[2]
$SNIPPET_UPDATE_MACHINE_STATUS
',

	SCRIPT_SET_WORKER_STATUS_DEFFERED_TO_REMOVING =>
'
local machineId = ARGV[1]
local status = redis.call("HGET", "$REDIS_KEY_WORKER_STATUS", machineId)
if status == "${MachineStatus.Deferred}" then
	status = "${MachineStatus.Removing}"
	$SNIPPET_UPDATE_MACHINE_STATUS
else
	print("Cannot change status " .. tostring(status) .. " for machine=" .. tostring(machineId))
end
',

			SCRIPT_GET_ALL_WORKER_TIMEOUTS =>
'
local poolId = ARGV[1]

local numElements = redis.call("ZINTERSTORE", "out", 2, "$REDIS_KEY_WORKER_DEFERRED_TIME", "${REDIS_KEY_WORKER_POOLS_PREFIX}" .. poolId)
if numElements > 0 then
	local result = {}
	local elements = redis.call("ZRANGE", "out", 0, -1)
	for index,machineId in ipairs(elements) do
		local score = tonumber(redis.call("ZSCORE", "$REDIS_KEY_WORKER_DEFERRED_TIME", machineId))
		table.insert(result, {id=machineId, time=score})
	end
	return cjson.encode(result)
else
	return "[]"
end


',



	];
}

abstract WorkerPoolPriority(Int) from Int to Int
{
	inline public function new (i)
		this = i;
	inline public function toInt() :Int
		return this;

}

abstract WorkerCount(Int) from Int to Int
{
	inline public function new (i)
		this = i;
	inline public function toInt() :Int
		return this;
}

/*
 * Helper defintions and tools for dealing with a JSON
 * description of the system.
 */
typedef InstancePoolJsonDump = {
	var pools :Array<{id :MachinePoolId, instances:Array<JsonDumpInstance>}>;
	var cpus :TypedDynamicObject<MachineId, Int>;
	var workerParameters :TypedDynamicObject<MachineId, JobParams>;
	var workers :TypedDynamicObject<MachineId, WorkerDefinition>;
	var status :TypedDynamicObject<MachineId, MachineStatus>;
	var jobs :TypedDynamicObject<ComputeJobId, MachineId>;
	var workerPoolMap :TypedDynamicObject<MachineId, MachinePoolId>;
	var targetWorkers :Dynamic<Int>;
	var maxInstances :Dynamic<Int>;
	var minInstances :Dynamic<Int>;
	var totalTargetInstances :Int;
	var available :Array<MachineId>;
	var timeouts :TypedDynamicObject<MachineId, Float>;
	var removed_record :TypedDynamicObject<MachineId, Dynamic>;
}

typedef JsonDumpInstance = {
	var id :MachineId;
	var jobs:Array<ComputeJobId>;
}

@:forward
abstract InstancePoolJson(InstancePoolJsonDump) from InstancePoolJsonDump
{
	inline function new (d: InstancePoolJsonDump)
		this = d;

	inline public function getMachine(id :MachineId) :JsonDumpInstance
	{
		for (pool in this.pools) {
			if (pool.instances != null) {
				for (machine in pool.instances) {
					if (machine.id == id) {
						return machine;
					}
				}
			}
		}
		return null;
	}

	inline public function getMachineStatus(id :MachineId) :MachineStatus
	{
		return Reflect.field(this.status, id);
	}

	inline public function getMachines() :Array<JsonDumpInstance>
	{
		var arr = [];
		for (pool in this.pools) {
			arr = arr.concat(pool.instances != null ? pool.instances : []);
		}
		return arr;
	}

	inline public function getAllMachinesForPool(poolId :MachinePoolId) :Array<MachineId>
	{
		var arr = [];
		for (pool in this.pools) {
			if (pool.id == poolId) {
				arr = pool.instances != null ? pool.instances.map(function(i) return i.id) : [];
			}
		}
		return arr;
	}

	inline public function getRemovedMachines() :Array<Dynamic>
	{
		var arr :Array<Dynamic> = [];
		for (key in this.removed_record.keys()) {
			var val :{time_removal:Float, time_added:Float} = this.removed_record.get(key);
			Reflect.setField(val, "time_removal", DateFormatTools.getFormattedDate(Std.parseFloat(Reflect.field(val, "time_removal"))));
			Reflect.setField(val, "time_added", DateFormatTools.getFormattedDate(Std.parseFloat(Reflect.field(val, "time_added"))));
			arr.push(val);
		}
		return arr;
	}

	inline public function getAvailableMachines(poolId :MachinePoolId) :Array<MachineId>
	{
		var arr :Array<MachineId> = [];
		for (pool in this.pools) {
			if (pool.id == poolId) {
				arr = pool.instances != null ? pool.instances.map(function(i) return i.id) : [];
			}
		}
		var activeStatuses = [MachineStatus.Available];
		var statusFilter = function(m :MachineStatus) {
			return activeStatuses.has(m);
		};

		arr = arr.filter(function(id) {
			return statusFilter(getMachineStatus(id));
		});
		return arr;
	}

	inline public function getRunningMachines(poolId :MachinePoolId) :Array<MachineId>
	{
		var arr :Array<MachineId> = [];
		for (pool in this.pools) {
			if (pool.id == poolId) {
				arr = pool.instances != null ? pool.instances.map(function(i) return i.id) : [];
			}
		}
		var activeStatuses = [MachineStatus.Available, MachineStatus.WaitingForRemoval, MachineStatus.Deferred];
		var statusFilter = function(m :MachineStatus) {
			return activeStatuses.has(m);
		};

		arr = arr.filter(function(id) {
			return statusFilter(getMachineStatus(id));
		});
		return arr;
	}

	inline public function getTargetWorkerCount(poolId :MachinePoolId) :WorkerCount
	{
		if (this.targetWorkers != null && Reflect.field(this.targetWorkers, poolId) != null) {
			var count :WorkerCount = Reflect.field(this.targetWorkers, poolId);
			return count;
		} else {
			return 0;
		}
	}

	inline public function getMaxWorkerCount(poolId :MachinePoolId) :WorkerCount
	{
		if (this.maxInstances != null && Reflect.field(this.maxInstances, poolId) != null) {
			var count :WorkerCount = Reflect.field(this.maxInstances, poolId);
			return count;
		} else {
			return 0;
		}
	}

	inline public function getMinWorkerCount(poolId :MachinePoolId) :WorkerCount
	{
		if (this.minInstances != null && Reflect.field(this.minInstances, poolId) != null) {
			var count :WorkerCount = Reflect.field(this.minInstances, poolId);
			return count;
		} else {
			return 0;
		}
	}

	inline public function getAvailableCpus(id :MachineId) :Int
	{
		return Reflect.field(Reflect.field(this, 'cpus'), id);
	}

	inline public function getTotalCpus(id :MachineId) :Int
	{
		return Reflect.field(Reflect.field(this, 'workerParameters'), id).cpus;
	}

	inline public function getAllAvailableCpus() :Int
	{
		// var cpus = Reflect.field(this, 'cpus');
		var count = 0;
		for (id in Reflect.fields(this.cpus)) {
			var c :Int = this.cpus[id];
			count += c;
		}
		return count;
	}

	public function getMachineRunningJob(id :ComputeJobId) :JsonDumpInstance
	{
		for (pool in this.pools) {
			if (pool.instances != null) {
				for (machine in pool.instances) {
					for (jobId in machine.jobs) {
						if (id == jobId) {
							return machine;
						}
					}
				}
			}
		}
		return null;
	}

	public function getJobsForPool(id :MachinePoolId) :Map<ComputeJobId, MachineId>
	{
		var map = new Map<ComputeJobId, MachineId>();
		for (pool in this.pools) {
			if (pool.id == id) {
				if (pool.instances != null) {
					for (machine in pool.instances) {
						if (machine.jobs != null) {
							for (jobId in machine.jobs) {
								map.set(jobId, machine.id);
							}
						}
					}
				}
			}
		}
		return map;
	}

	inline public function getTimeout(id :MachineId) :TimeStamp
	{
		return this.timeouts[id] != null ? new TimeStamp(new Milliseconds(this.timeouts[id])) : null;
	}

	inline public function getTimeoutString(id :MachineId) :String
	{
		return this.timeouts[id] != null ? new TimeStamp(new Milliseconds(this.timeouts[id])) : null;
	}


	inline public function toString() :String
	{
		return Json.stringify(this, null, '  ');
	}
}