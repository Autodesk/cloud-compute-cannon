package ccc.compute.server;

import ccc.compute.shared.TypedDynamicObject;

import haxe.DynamicAccess;
import haxe.Json;
import haxe.io.Bytes;

import js.Node;
import js.npm.RedisClient;
import js.npm.redis.RedisLuaTools;

import org.msgpack.MsgPack;

import promhx.Promise;
import promhx.RedisPromises;
import promhx.deferred.DeferredPromise;

import ccc.compute.server.ComputeTools;
import ccc.compute.server.InstancePool;

using Lambda;
using promhx.PromiseTools;

typedef QueueObject<T> = {> QueueJob<T>,
	var stats :Stats;
}

typedef ProcessResult = {
	var assigned :Array<JobId>;
	var remaining :Array<JobId>;
}

/**
 * Represents a queue of compute jobs in Redis
 * Lots of ideas taken from http://blogs.bronto.com/engineering/reliable-queueing-in-redis-part-1/
 */
class ComputeQueue
{
	/**
	 * Set up the job queue monitor for every second. Move this to a parameter eventually.
	 * This removes jobs that have been working too long, it puts them back in the queue.
	 */
	public static function startPoll(redis :RedisClient, ?interval :Int = 5000) :Void->Void
	{
		var id = Node.setInterval(checkTimeouts.bind(redis), interval);
		return function() {
			Node.clearInterval(id);
		};
	}

	public static function init(redis :RedisClient) :Promise<Bool>//You can chain this to a series of piped promises
	{
		for (key in scripts.keys()) {
			var script = scripts.get(key);
			if (script.indexOf('local SCRIPTID') == -1) {
				script = 'local SCRIPTID = "$key"\n' + script;
				scripts.set(key, script);
			}
		}
		return RedisLuaTools.initLuaScripts(redis, scripts)
			.then(function(scriptIdsToShas :Map<String, String>) {
				SCRIPT_SHAS = scriptIdsToShas;
				//This helps with debugging the lua scripts, uses the name instead of the hash
				SCRIPT_SHAS_TOIDS = new Map();
				for (key in SCRIPT_SHAS.keys()) {
					SCRIPT_SHAS_TOIDS[SCRIPT_SHAS[key]] = key;
				}
				return SCRIPT_SHAS != null;
			});
	}

	public static function generateJobId(redis :RedisClient) :Promise<JobId>
	{
		var deferred = new promhx.deferred.DeferredPromise();
		redis.incr(REDIS_KEY_JOBID_COUNTER, function(err, val) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			deferred.resolve(Std.string(val));
		});
		return deferred.boundPromise;
	}

	public static function enqueue<T>(redis :RedisClient, job :QueueJob<T>) :Promise<QueueObject<T>>
	{
		Assert.notNull(job);
		Assert.notNull(job.id);
		Assert.notNull(job.item);
		Assert.notNull(job.parameters);
		Assert.notNull(job.parameters.maxDuration);

		var stats = new Stats().setEnqueueTime();

		var queueObj :QueueObject<T> = {
			id: job.id,
			item: job.item,
			parameters: job.parameters,
			stats: stats
		}

		//Add the item to a hash of values, the only place where the
		//item value is stored, and add the id to the pending list
		//This is an atomic operation.
		return evaluateLuaScript(redis, SCRIPT_ENQUEUE, [Json.stringify(queueObj), Date.now().getTime()])
			.then(function(_) {
				return queueObj;
			});
	}

	public static function enqueueAll<T>(redis :RedisClient, items :Array<QueueJob<T>>):Promise<Array<QueueObject<T>>>
	{
		return Promise.whenAll(items.map(function(job) return enqueue(redis, job)));
	}

	/**
	 * Pulls a job from the pending queue and puts it in the
	 * 'working' state. There is a max time this job is allowed
	 * to be in the working state, after which it is push back
	 * on to the pending queue.
	 *
	 * [returns] The QueueObject
	 */
	public static function processPending(redis :RedisClient) :Promise<ProcessResult>
	{
		return evaluateLuaScript(redis, SCRIPT_PROCESS_PENDING, [Date.now().getTime()])
			.then(Json.parse);
	}

	/**
	 * Checks all working jobs, if any have expired, pushes them
	 * back on the pending queue, and increments the requeueing
	 * stats.
	 * @param  redis :RedisClient  [description]
	 * @return       [description]
	 */
	public static function checkTimeouts(redis :RedisClient) :Promise<Array<JobId>>
	{
		return evaluateLuaScript(redis, SCRIPT_CHECK_TIMEOUTS, [Date.now().getTime()])
			.then(function(arr :Array<JobId>) {
				return arr;
			});
	}

	public static function getAllJobIds(redis :RedisClient) :Promise<Array<JobId>>
	{
		return RedisPromises.hkeys(redis, REDIS_KEY_STATUS)
			.then(function(arr) {
				return cast arr;
			});
	}

	public static function isJob(redis :RedisClient, jobId :JobId) :Promise<Bool>
	{
		return RedisPromises.hexists(redis, REDIS_KEY_STATUS, jobId);
	}

	public static function getJob<T>(redis :RedisClient, jobId :JobId) :Promise<T>
	{
		var deferred = new promhx.deferred.DeferredPromise();
		redis.hget(REDIS_KEY_VALUES, jobId.toString(), function(err, val) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			if (val != null) {
				deferred.resolve(Json.parse(val));
			} else {
				redis.get(REDIS_KEY_JOB_KEY_PREFIX + jobId.toString(), function(err, val) {
					if (err != null) {
						deferred.boundPromise.reject(err);
						return;
					}
					deferred.resolve(Json.parse(val));
				});
			}
		});
		return deferred.boundPromise;
	}

	public static function getPendingJobIds(redis :RedisClient) :Promise<Array<JobId>>
	{
		var deferred = new promhx.deferred.DeferredPromise();
		redis.lrange(REDIS_KEY_PENDING, 0, -1, function(err, val) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			deferred.resolve(cast val);
		});
		return deferred.boundPromise;
	}

	public static function getWorkingJobIds(redis :RedisClient) :Promise<Array<JobId>>
	{
		var deferred = new promhx.deferred.DeferredPromise();
		redis.zrange(REDIS_KEY_WORKING, 0, -1, function(err, val :Array<Dynamic>) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			deferred.resolve(cast val);
		});
		return deferred.boundPromise;
	}

	public static function getParameters(redis :RedisClient, jobId :JobId) :Promise<JobParams>
	{
		var deferred = new promhx.deferred.DeferredPromise();
		redis.hget(REDIS_KEY_PARAMETERS, jobId, function(err, val) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			deferred.resolve(Json.parse(val));
		});
		return deferred.boundPromise;
	}

	public static function getJobDescription<T>(redis :RedisClient, jobId :JobId) :Promise<QueueJobDefinition<T>>
	{
		return evaluateLuaScript(redis, SCRIPT_GET_JOB_DEFINITION, [jobId])
			.then(Json.parse);
	}

	public static function getJobDescriptionFromComputeId<T>(redis :RedisClient, computeId :ComputeJobId) :Promise<QueueJobDefinition<T>>
	{
		return evaluateLuaScript(redis, SCRIPT_GET_JOB_DEFINITION_FROM_COMPUTE_ID, [computeId])
			.then(Json.parse);
	}

	public static function getJobStats(redis :RedisClient, jobId :JobId) :Promise<Stats>
	{
		return evaluateLuaScript(redis, SCRIPT_GETSTATS, [jobId, Date.now().getTime()])
			.then(function(s) {
				var obj = Json.parse(s);
				return cast obj;
			});
	}

	public static function getStatus(redis :RedisClient, jobId :JobId) :Promise<JobStatusUpdate>
	{
		return RedisPromises.hget(redis, REDIS_KEY_STATUS, jobId)
			.then(function(s) {
				var obj = Json.parse(s);
				return cast obj;
			});
	}

	public static function getJobStatus(redis :RedisClient, jobId :JobId) :Promise<JobStatusBlob>
	{
		return evaluateLuaScript(redis, SCRIPT_JOB_STATUS, [jobId])
			.then(function(s) {
				var obj = Json.parse(s);
				return cast obj;
			});
	}

	public static function getJobStatuses(redis :RedisClient) :Promise<TypedDynamicObject<JobId,JobStatusBlob>>
	{
		return evaluateLuaScript(redis, SCRIPT_JOB_STATUSES, [])
			.then(function(s :String) {
				var obj = Json.parse(s);
				return obj;
			});
	}

	public static function getWorkerIdForJob(redis :RedisClient, jobId :JobId) :Promise<MachineId>
	{
		return RedisPromises.hget(redis, REDIS_KEY_JOB_ID_TO_COMPUTE_ID, jobId)
			.pipe(function(computeJobId :ComputeJobId) {
				if (computeJobId != null) {
					return RedisPromises.hget(redis, InstancePool.REDIS_KEY_WORKER_JOB_MACHINE_MAP, computeJobId);
				} else {
					return Promise.promise(null);
				}
			});
	}

	public static function removeJob<T>(redis :RedisClient, jobId :JobId) :Promise<QueueObject<T>>
	{
		Assert.notNull(jobId);
		return evaluateLuaScript(redis, SCRIPT_REMOVE_JOB, [jobId, Date.now().getTime()])
			.then(function(s :String) {
				var obj = Json.parse(s);
				return obj;
			});
	}


	public static function jobFinalized<T>(redis :RedisClient, computeJobId :ComputeJobId) :Promise<Bool>
	{
		Assert.notNull(computeJobId);
		return evaluateLuaScript(redis, SCRIPT_FINALIZED_COMPUTE_JOB, [computeJobId, Date.now().getTime()])
			.thenTrue();
	}

	public static function removeComputeJob<T>(redis :RedisClient, computeJobId :ComputeJobId) :Promise<QueueObject<T>>
	{
		Assert.notNull(computeJobId);
		return evaluateLuaScript(redis, SCRIPT_REMOVE_COMPUTE_JOB, [computeJobId, Date.now().getTime()])
			.then(function(s :String) {
				var obj = Json.parse(s);
				return obj;
			});
	}

	public static function removeFinishedJobFromDatabase<T>(redis :RedisClient, jobId :JobId) :Promise<Bool>
	{
		Assert.notNull(jobId);
		return evaluateLuaScript(redis, SCRIPT_REMOVE_ALL_JOB_DATA, [jobId])
			.thenTrue();
	}

	public static function finishComputeJob<T>(redis :RedisClient, computeJobId :ComputeJobId, status :JobFinishedStatus, ?error :Dynamic) :Promise<QueueJobDefinitionDocker>
	{
		if (error != null) {
			error = Json.stringify(error);
		}
		return evaluateLuaScript(redis, SCRIPT_FINISHED_COMPUTE_JOB, [computeJobId, status, Date.now().getTime(), error])
			.then(function(s :String) {
				var obj = Json.parse(s);
				return obj;
			});
	}

	public static function setComputeJobWorkingStatus(redis :RedisClient, computeJobId :ComputeJobId, status :JobWorkingStatus) :Promise<Int>
	{
		return RedisPromises.hset(redis, REDIS_KEY_COMPUTEJOB_WORKING_STATE, computeJobId, status);
	}

	public static function getComputeJobWorkingStatus(redis :RedisClient, computeJobId :ComputeJobId) :Promise<JobWorkingStatus>
	{
		return RedisPromises.hget(redis, REDIS_KEY_COMPUTEJOB_WORKING_STATE, computeJobId);
	}

	public static function requeueJob<T>(redis :RedisClient, computeJobId :ComputeJobId) :Promise<Bool>
	{
		return evaluateLuaScript(redis, SCRIPT_REQUEUE, [computeJobId, Date.now().getTime()])
			.thenTrue();
	}

	public static function setAutoscaling(redis :RedisClient, autoscale :Bool) :Promise<Bool>
	{
		return RedisPromises.set(redis, REDIS_KEY_AUTOSCALING_ENABLED, autoscale == true ? 'true':'false');
	}

	public static function toJson(client :RedisClient) :Promise<QueueJsonDump>
	{
		return evaluateLuaScript(client, SCRIPT_TO_JSON)
			.then(Json.parse);
	}

	public static function dumpJson(client :RedisClient) :Promise<QueueJsonDump>
	{
		return toJson(client)
			.then(function(dump) {
				return dump;
			});
	}

	static function evaluateLuaScript<T>(redis :RedisClient, scriptKey :String, ?args :Array<Dynamic>) :Promise<T>
	{
		return RedisLuaTools.evaluateLuaScript(redis, SCRIPT_SHAS[scriptKey], null, args, SCRIPT_SHAS_TOIDS, scripts);
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
		client.keys(PREFIX + '*', function(err, keys :Array<Dynamic>) {
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

	public static function finishJob<T>(redis :RedisClient, jobId :JobId, ?status :JobFinishedStatus, ?error :Dynamic)
	{
		Assert.notNull(jobId);
		if (status == null) {
			status = JobFinishedStatus.Success;
		}
		return RedisPromises.hget(redis, REDIS_KEY_JOB_ID_TO_COMPUTE_ID, jobId)
			.pipe(function(computeJobId) {
				return finishComputeJob(redis, computeJobId, status, error);
			});
	}

	public static function getComputeJobId(redis :RedisClient, jobId :JobId) :Promise<ComputeJobId>
	{
		return getStatus(redis, jobId)
			.then(function(jobStatusBlob) {
				return jobStatusBlob.computeJobId;
			});
	}
#if tests
	/**
	 * This does the logic normally in the Job(s) objects.
	 * @param  redis        :RedisClient  [description]
	 * @param  computeJobId :ComputeJobId [description]
	 * @return              [description]
	 */
	public static function finishAndFinalizeJob(redis :RedisClient, jobId :JobId, status :JobFinishedStatus) :Promise<ComputeJobId>
	{
		return getComputeJobId(redis, jobId)
			.pipe(function(computeJobId) {
				//This is normally handled by the Job object
				return finishComputeJob(redis, computeJobId, status)
					.pipe(function(_) {
						return jobFinalized(redis, computeJobId)
							.pipe(function(_) {
								return InstancePool.removeJob(redis, computeJobId);
							})
							.pipe(function(_) {
								return processPending(redis);
							});
					})
					.then(function(_) {
						return computeJobId;
					});
			});
	}

#end

	/* When we call a Lua script, use the SHA of the already uploaded script for performance */
	static var SCRIPT_SHAS :Map<String, String>;
	static var SCRIPT_SHAS_TOIDS :Map<String, String>;

	inline static var PREFIX = 'compute_queue${SEP}';
	inline static var REDIS_KEY_PENDING = '${PREFIX}pending'; //LIST <JobId>
	inline static var REDIS_KEY_WORKING = '${PREFIX}working'; //SORTED SET <JobId>

	public inline static var REDIS_KEY_STATUS = '${PREFIX}job_status'; //Hash <JobId, JobStatus>
	public inline static var REDIS_KEY_STATUS_FINISHED = '${PREFIX}job_status_finished'; //Hash <JobId, JobFinishedStatus>
	public inline static var REDIS_KEY_JOB_KEY_PREFIX = '${PREFIX}job_'; //Publishes jobIds as they are timedout
	public inline static var REDIS_CHANNEL_STATUS = '${PREFIX}job_status_channel'; //Publishes jobIds as they are timedout

	inline static var REDIS_KEY_JOBID_COUNTER = '${PREFIX}jobid_count'; //KEY
	inline static var REDIS_KEY_VALUES = '${PREFIX}values'; //Hash <JobId, Job>
	inline static var REDIS_KEY_PARAMETERS = '${PREFIX}parameters'; //Hash <JobId, Parameters>
	inline static var REDIS_KEY_STATS = '${PREFIX}stats'; //Hash <JobId, Stats>
	inline static var REDIS_KEY_JOB_ID_TO_COMPUTE_ID = '${PREFIX}job_compute_id'; //Hash <JobId, ComputeJobId>
	inline static var REDIS_KEY_COMPUTE_ID_TO_JOB_ID = '${PREFIX}compute_id_job'; //Hash <ComputeJobId, JobId>
	inline static var REDIS_KEY_AUTOSCALING_ENABLED = '${PREFIX}autoscaling_enabled'; //key
	inline static var REDIS_KEY_COMPUTEJOB_WORKING_STATE = '${PREFIX}job_working_state'; //Hash <ComputeJobId, JobWorkingStatus>

	//This is the last taken and actually builds and runs and monitors the docker
	//job in reality
	inline static var REDIS_KEY_PROCESS = '${PREFIX}process'; //List <{JobId, MachineId}>

	inline public static var REDIS_CHANNEL_LOG_INFO = '${PREFIX}log';
	inline public static var REDIS_CHANNEL_LOG_ERROR = '${PREFIX}error';

	/**
	 * Redis Lua script Ids.
	 */
	inline static var SCRIPT_ENQUEUE = '${PREFIX}enqueue';
	inline static var SCRIPT_REQUEUE = '${PREFIX}requeue';
	inline static var SCRIPT_REMOVE_JOB = '${PREFIX}remove_job';
	inline static var SCRIPT_REMOVE_COMPUTE_JOB = '${PREFIX}compute_job_remove';
	inline static var SCRIPT_FINISHED_COMPUTE_JOB = '${PREFIX}compute_job_finished';
	inline static var SCRIPT_FINALIZED_COMPUTE_JOB = '${PREFIX}compute_job_finalized';
	// inline static var SCRIPT_GET_QUEUE_OBJECT = '${PREFIX}get_queue_obj';
	inline static var SCRIPT_CHECK_TIMEOUTS = '${PREFIX}check_timeouts';
	inline static var SCRIPT_GETSTATS = '${PREFIX}get_stats';
	inline static var SCRIPT_PROCESS_PENDING = '${PREFIX}process_pending';
	inline static var SCRIPT_TO_JSON = '${PREFIX}tojson';
	inline static var SCRIPT_GET_JOB_DEFINITION = '${PREFIX}get_job_definition';
	inline static var SCRIPT_GET_JOB_DEFINITION_FROM_COMPUTE_ID = '${PREFIX}get_job_definition_from_compute_id';
	inline static var SCRIPT_REMOVE_ALL_JOB_DATA = '${PREFIX}remove_job_data';
	inline static var SCRIPT_JOB_STATUSES = '${PREFIX}get_job_statuses';
	inline static var SCRIPT_JOB_STATUS = '${PREFIX}get_job_status';

	/**
	 * Re-used snippets of Lua code
	 */

	 	public static var SNIPPET_SET_JOB_STATUS_BLOB =
//Expects jobId, ?statusBlob<JobStatusUpdate>
'
if not statusBlob then
	return {err=SCRIPTID .. " job=" .. jobId .. " no statusBlob"}
end
statusBlob.computeJobId = redis.call("HGET", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId)
statusBlob.jobId = jobId
statusBlob.job = cjson.decode(redis.call("HGET", "$REDIS_KEY_VALUES", jobId))
local statusBlobString = cjson.encode(statusBlob)
redis.call("HSET", "$REDIS_KEY_STATUS", jobId, statusBlobString)
redis.call("SET", "$REDIS_CHANNEL_STATUS", statusBlobString)
redis.call("PUBLISH", "$REDIS_CHANNEL_STATUS", statusBlobString) --JobStatusUpdate
';

	public static var SNIPPET_SET_JOB_STATUS =
//Expects jobId, jobStatus
'
if not jobStatus then
	return {err=SCRIPTID .. " job=" .. jobId .. " no jobStatus"}
end
local statusBlob = cjson.decode(redis.call("HGET", "$REDIS_KEY_STATUS", jobId))
statusBlob.JobStatus = jobStatus
$SNIPPET_SET_JOB_STATUS_BLOB
';

	public static var SNIPPET_SET_JOB_FINISHED_STATUS =
//Expects jobId, jobFinishedStatus, jobFinishedError
'
if not jobFinishedStatus then
	return {err=SCRIPTID .. " job=" .. jobId .. " no jobFinishedStatus"}
end

local statusBlob = cjson.decode(redis.call("HGET", "$REDIS_KEY_STATUS", jobId))
if statusBlob.JobStatus ~= "${JobStatus.Working}" then
	if jobFinishedStatus ~= "${JobFinishedStatus.Killed}" then
		return {err=SCRIPTID .. " job=" .. jobId .. " set jobFinishedStatus=" .. jobFinishedStatus .. " but JobStatus != ${JobStatus.Working}"}
	end
end

if statusBlob.JobStatus == "${JobStatus.Finalizing}" or statusBlob.JobStatus == "${JobStatus.Finished}" then
	return {err=SCRIPTID .. " job=" .. jobId .. " set JobFinishedStatus=" .. jobFinishedStatus .. " but JobStatus " .. redis.call("HGET", "$REDIS_KEY_STATUS", jobId)}
end

statusBlob.JobFinishedStatus = jobFinishedStatus
statusBlob.JobStatus = "${JobStatus.Finalizing}"

local jobFinishedError = jobFinishedError or nil
statusBlob.error = jobFinishedError or nil
$SNIPPET_SET_JOB_STATUS_BLOB
';


	public static var SNIPPET_ERROR =
//Expects message string
'
redis.call("PUBLISH", "$REDIS_CHANNEL_LOG_ERROR", message) ; print(message)
';

	public static var SNIPPET_INFO =
//Expects message string
'
redis.call("PUBLISH", "$REDIS_CHANNEL_LOG_INFO", message) ; print(message)
';

	static var SNIPPET_GET_STATSOBJECT =
'
local statsPacked = redis.call("HGET", "$REDIS_KEY_STATS", jobId)
if not statsPacked then
	return {err=SCRIPTID .. " No stats object for job=" .. jobId}
end
local stats = cmsgpack.unpack(statsPacked)
';
	static var SNIPPET_GET_QUEUEOBJECT =
'
local jobParameters = cjson.decode(redis.call("HGET", "$REDIS_KEY_PARAMETERS", jobId))
local item = cjson.decode(redis.call("HGET", "$REDIS_KEY_VALUES", jobId))
local computeJobId = redis.call("HGET", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId)
local queueObject = {id=jobId, computeJobId=computeJobId, item=item, parameters=jobParameters, stats=stats}
';

	static var SNIPPET_GET_JOB_DEFINITION =
'
if type(jobId) == "boolean" then
	return {err="jobId is a boolean"}
end
local stats = cmsgpack.unpack(redis.call("HGET", "$REDIS_KEY_STATS", jobId))
local jobParameters = cjson.decode(redis.call("HGET", "$REDIS_KEY_PARAMETERS", jobId))
local item = cjson.decode(redis.call("HGET", "$REDIS_KEY_VALUES", jobId))
local computeJobId = redis.call("HGET", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId)

${InstancePool.SNIPPET_GET_MACHINE_FOR_JOB}

local result = {id=jobId, computeJobId=computeJobId, item=item, parameters=jobParameters, stats=stats, worker=cjson.decode(machineDef)}
return cjson.encode(result)
';

	public static var SNIPPET_PROCESS_PENDING =
'
local pendingjobId = redis.call("RPOP", "$REDIS_KEY_PENDING")

local jobsWithoutWorkers
local jobsAssigned

while pendingjobId do
	local jobId = pendingjobId --Scoping this so there is no interference with a jobId defined outside the block
	local jobParamsString = redis.call("HGET", "$REDIS_KEY_PARAMETERS", jobId)
	local jobParameters = cjson.decode(jobParamsString) --JobParams

	${InstancePool.SNIPPET_FIND_MACHINE_FOR_JOB}

	if machineId then
		--Update the stats object
		$SNIPPET_GET_STATSOBJECT
		stats[${Stats.INDEX_LAST_DEQUEUE_TIME}] = time
		stats[${Stats.INDEX_DEQUEUE_COUNT}] = stats[${Stats.INDEX_DEQUEUE_COUNT}] + 1
		redis.call("HSET", "$REDIS_KEY_STATS", jobId, cmsgpack.pack(stats))

		--Create a computeJobId and map to the job id.
		--This prevents old jobs being returned after timing out
		local computeJobId = jobId .. "${Constants.JOB_ID_ATTEMPT_SEP}"  .. tostring(stats[${Stats.INDEX_DEQUEUE_COUNT}])
		redis.call("HSET", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId, computeJobId)
		redis.call("HSET", "$REDIS_KEY_COMPUTE_ID_TO_JOB_ID", computeJobId, jobId)

		--Put the job on the working set, with the stale time
		local staleTime = time + jobParameters.maxDuration

		redis.call("ZADD", "$REDIS_KEY_WORKING", staleTime, jobId)

		--Add it to the machine on the InstancePool
		${InstancePool.SNIPPET_ADD_JOB_TO_MACHINE}

		--Set the status
		local jobStatus = "${JobStatus.Working}"
		local statusBlob = cjson.decode(redis.call("HGET", "$REDIS_KEY_STATUS", jobId))
		$SNIPPET_SET_JOB_STATUS

		if not jobsAssigned then
			jobsAssigned = {}
		end

		local message = "Job=" .. jobId .. " is now assigned to machine=" .. machineId .. " computeJobId=" .. computeJobId .. " timeout(milliseconds)=" .. tostring(jobParameters.maxDuration)
		$SNIPPET_INFO

		table.insert(jobsAssigned, jobId)
	else
		--local message = "Job=" .. jobId .. " no machine found"
		--$ SNIPPET_INFO
		if not jobsWithoutWorkers then
			jobsWithoutWorkers = {}
		end
		table.insert(jobsWithoutWorkers, jobId)
	end

	pendingjobId = redis.call("RPOP", "$REDIS_KEY_PENDING")
end

--Push the jobs that could not be matched with machines back on the queue
--This keeps the priority order.
if jobsWithoutWorkers then

	--local message = tostring(#jobsWithoutWorkers) .. " jobs without assigned workers"
	--$ SNIPPET_INFO
	for i=#jobsWithoutWorkers, 1, -1 do
		redis.call("RPUSH", "$REDIS_KEY_PENDING", jobsWithoutWorkers[i])
	end
end

if (redis.call("GET", "$REDIS_KEY_AUTOSCALING_ENABLED") or "true") == "true" then
	--local message = "Autoscaling..."
	--$ SNIPPET_INFO
	--print("pending count=" .. tostring(redis.call("LLEN", "$REDIS_KEY_PENDING")))
	if redis.call("LLEN", "$REDIS_KEY_PENDING") > 0 then
		local pendingJobs = redis.call("LRANGE", "$REDIS_KEY_PENDING", 0, -1)
		local required = {cpus=0}
		for index,jobId in ipairs(pendingJobs) do
			local parameters =  cjson.decode(redis.call("HGET", "$REDIS_KEY_PARAMETERS", jobId))
			required.cpus = required.cpus + parameters.cpus
		end
		${InstancePool.SNIPPET_SCALE_WORKERS_UP}
	else
		${InstancePool.SNIPPET_SCALE_WORKERS_DOWN}
	end
end
';

	static var SNIPPET_FINISH_JOB =
//Expects jobId,jobFinishedStatus,time,jobFinishedError
'
if not redis.call("ZRANK", "$REDIS_KEY_WORKING", jobId) then
	return {err="Job " .. jobId .. " is not in working mode"}
end

local computeJobId = redis.call("HGET", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId)
--local message = "Finishing job=" .. jobId .. " computeJobId=" .. computeJobId .. "   jobFinishedStatus=" .. jobFinishedStatus
-- $ SNIPPET_INFO

--Update the stats object
$SNIPPET_GET_STATSOBJECT
stats[${Stats.INDEX_FINISH_TIME}] = time
redis.call("HSET", "$REDIS_KEY_STATS", jobId, cmsgpack.pack(stats))

--Delete the job from the queue
redis.call("ZREM", "$REDIS_KEY_WORKING", jobId)

$SNIPPET_SET_JOB_FINISHED_STATUS
';

	static var SNIPPET_REMOVE_JOB_RECORD =
//Expects jobId
'
local statusBlobString = redis.call("HGET", "$REDIS_KEY_STATUS", jobId)
if not statusBlobString then
	print("Job already removed " .. jobId)
	return --Job already removed
end
local statusBlob = cjson.decode(statusBlobString)
local jobItem = redis.call("HGET", "$REDIS_KEY_VALUES", jobId)

--Delete all the records of the job
redis.call("HDEL", "$REDIS_KEY_STATS", jobId)
redis.call("ZREM", "$REDIS_KEY_WORKING", jobId)
redis.call("HDEL", "$REDIS_KEY_VALUES", jobId)
redis.call("HDEL", "$REDIS_KEY_PARAMETERS", jobId)
redis.call("HDEL", "$REDIS_KEY_STATUS", jobId)
redis.call("HDEL", "$REDIS_KEY_COMPUTEJOB_WORKING_STATE", jobId)


if statusBlob.JobStatus == "${JobStatus.Pending}" then
	local removedCount = redis.call("LREM", "$REDIS_KEY_PENDING", 1, jobId)
	print("Removing from the pending queue " .. jobId .. ", actually removed=" .. tostring(removedCount))
end

local computeJobId = redis.call("HGET", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId)
if computeJobId then
	redis.call("HDEL", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId)
	redis.call("HDEL", "$REDIS_KEY_COMPUTE_ID_TO_JOB_ID", computeJobId)
	redis.call("HDEL", "$REDIS_KEY_COMPUTEJOB_WORKING_STATE", computeJobId)
end
';

/**
 * Expects: computeJobId, time
 */
	public static var SNIPPET_REQUEUE_COMPUTE_JOB =
'
local jobId = redis.call("HGET", "$REDIS_KEY_COMPUTE_ID_TO_JOB_ID", computeJobId)

if not jobId then
	local message = "Requeuing but no jobId for computeId=" .. tostring(computeJobId)
	$SNIPPET_ERROR
else
	if redis.call("HGET", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId) ~= computeJobId then
		local message = "job (" .. jobId .. ") has a new computeJobId(" .. computeJobId .. "), this job has already been requeued"
		$SNIPPET_ERROR
	else
		local jobStatus = redis.call("HGET", "$REDIS_KEY_STATUS", jobId)
		if jobStatus == "${JobStatus.Finished}" then
			local message = "job (" .. jobId .. ") has already finished, cannot be requeued"
			$SNIPPET_ERROR
		else
			local message = "Requeuing job=" .. jobId .. " computeJobId=" .. computeJobId
			$SNIPPET_INFO

			--Push the jobId back on the pending queue, but at the FRONT of the queue,
			--not the back since this is a reqeue, and should be prioritized before currend pending jobs
			redis.call("RPUSH", "$REDIS_KEY_PENDING", jobId)
			--Delete from the working set
			redis.call("ZREM", "$REDIS_KEY_WORKING", jobId)
			--Update the stats object with this change
			$SNIPPET_GET_STATSOBJECT
			stats[${Stats.INDEX_REQUEUE_COUNT}] = stats[${Stats.INDEX_REQUEUE_COUNT}] + 1
			stats[${Stats.INDEX_LAST_REQUEUE_TIME}] = time
			redis.call("HSET", "$REDIS_KEY_STATS", jobId, cmsgpack.pack(stats))
			--Remove the computeJobId, so that if it comes back, there will be no job matching this version
			--Remove the job from the pool?
			redis.call("HDEL", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId)
			redis.call("HDEL", "$REDIS_KEY_COMPUTE_ID_TO_JOB_ID", computeJobId)
			${InstancePool.SNIPPET_REMOVE_JOB}

			local statusBlob = cjson.decode(redis.call("HGET", "$REDIS_KEY_STATUS", jobId))
			local jobStatus = "${JobStatus.Pending}"
			$SNIPPET_SET_JOB_STATUS
			end
		end
	end
	';


		/* The literal Redis Lua scripts. These allow non-race condition and performant operations on the DB*/
		static var scripts :Map<String, String> = [
			SCRIPT_ENQUEUE =>
	'
	local job = cjson.decode(ARGV[1])
	local time = tonumber(ARGV[2])
	local jobId = job.id

	redis.call("HSET", "$REDIS_KEY_VALUES", jobId, cjson.encode(job.item))
	redis.call("HSET", "$REDIS_KEY_PARAMETERS", jobId, cjson.encode(job.parameters))
	redis.call("LPUSH", "$REDIS_KEY_PENDING", jobId)
	redis.call("HSET", "$REDIS_KEY_STATS", jobId, cmsgpack.pack(job.stats))

	local statusBlob = {jobId=jobId,JobStatus="${JobStatus.Pending}",JobFinishedStatus="${JobFinishedStatus.None}"}
	$SNIPPET_SET_JOB_STATUS_BLOB
	$SNIPPET_PROCESS_PENDING
	',

	/**
	 * Takes jobs off the queue if it can match them with slots in the compute
	 * pool. If they are taken off the queue, a {jobId:jobId, workerId:workderId}
	 * object is posted to a list that is then subsequently consumed and the
	 * actual job started.
	 */
			SCRIPT_PROCESS_PENDING =>
	'
	local time = tonumber(ARGV[1])

	$SNIPPET_PROCESS_PENDING

	return cjson.encode({assigned=jobsAssigned, remaining=jobsWithoutWorkers})
	',
			SCRIPT_REQUEUE =>
	'
local computeJobId = ARGV[1]
local time = tonumber(ARGV[2])

if not computeJobId then
	return {err="Must provide computeJobId"}
end

local jobId = redis.call("HGET", "$REDIS_KEY_COMPUTE_ID_TO_JOB_ID", computeJobId)

$SNIPPET_REQUEUE_COMPUTE_JOB

$SNIPPET_PROCESS_PENDING
',
		SCRIPT_CHECK_TIMEOUTS =>
'
local time = tonumber(ARGV[1])
--These are all the jobIds whose expire time has past (current time)
local timedOutIds = redis.call("ZRANGEBYSCORE", "$REDIS_KEY_WORKING", 0, time)
if timedOutIds then
	for i = 1, #timedOutIds do
		local jobId = timedOutIds[i]

		local message = "TIMEOUT job=" .. jobId
		$SNIPPET_ERROR

		local jobFinishedStatus = "${JobFinishedStatus.TimeOut}"
		local jobFinishedError = nil
		$SNIPPET_FINISH_JOB
	end
	--Remove them
	--redis.call("ZREMRANGEBYSCORE", "$REDIS_KEY_WORKING", 0, time)
	return timedOutIds
end
',
// 		SCRIPT_GET_QUEUE_OBJECT =>
// '
// local jobId = ARGV[1]
// $SNIPPET_GET_STATSOBJECT
// $SNIPPET_GET_QUEUEOBJECT
// return cjson.encode(queueObject)
// ',

		SCRIPT_GET_JOB_DEFINITION =>
'
local jobId = ARGV[1]
local computeJobId = redis.call("HGET", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId)
$SNIPPET_GET_JOB_DEFINITION
',

		SCRIPT_GET_JOB_DEFINITION_FROM_COMPUTE_ID =>
'
local computeJobId = ARGV[1]
local jobId = redis.call("HGET", "$REDIS_KEY_COMPUTE_ID_TO_JOB_ID", computeJobId)
if type(jobId) == "boolean" then
	return {err="SCRIPT_GET_JOB_DEFINITION_FROM_COMPUTE_ID no jobId for computeJobId=" .. tostring(computeJobId)}
end
$SNIPPET_GET_JOB_DEFINITION
',

		SCRIPT_FINISHED_COMPUTE_JOB =>
'
local computeJobId = ARGV[1]
local jobFinishedStatus = ARGV[2]
local time = tonumber(ARGV[3])
local jobFinishedError = ARGV[4]
if tostring(jobFinishedError) == "undefined" then
	jobFinishedError = nil
end

if not jobFinishedStatus then
	return {err="SCRIPT_FINISHED_COMPUTE_JOB no jobFinishedStatus"}
end

if not computeJobId then
	return {err="SCRIPT_FINISHED_COMPUTE_JOB no computeJobId"}
end

if not time then
	return {err="SCRIPT_FINISHED_COMPUTE_JOB no time"}
end

local jobId = redis.call("HGET", "$REDIS_KEY_COMPUTE_ID_TO_JOB_ID", computeJobId)

if not jobId then
	local message = "SCRIPT_FINISHED_COMPUTE_JOB no jobId for computeId=" .. tostring(computeJobId)
	$SNIPPET_ERROR
	return {err=message}
end

--local message = "Finished called for computeId=" .. tostring(computeJobId) .. " jobId=" .. jobId
--$ SNIPPET_INFO

$SNIPPET_FINISH_JOB
$SNIPPET_PROCESS_PENDING
$SNIPPET_GET_QUEUEOBJECT
return cjson.encode(queueObject)
',

		SCRIPT_FINALIZED_COMPUTE_JOB =>
'
local computeJobId = ARGV[1]
local time = tonumber(ARGV[2])

if not computeJobId then
	return {err="SCRIPT_FINALIZED_COMPUTE_JOB no computeJobId"}
end

local jobId = redis.call("HGET", "$REDIS_KEY_COMPUTE_ID_TO_JOB_ID", computeJobId)

if not jobId then
	local message = "SCRIPT_FINALIZED_COMPUTE_JOB no jobId for computeId=" .. tostring(computeJobId)
	$SNIPPET_ERROR
	return {err=message}
end

local statusBlob = cjson.decode(redis.call("HGET", "$REDIS_KEY_STATUS", jobId))

local jobStatus = "${JobStatus.Finished}"
$SNIPPET_SET_JOB_STATUS

--Delete all computeId records of the job, since they are no longer needed
redis.call("HDEL", "$REDIS_KEY_COMPUTEJOB_WORKING_STATE", jobId)
redis.call("HDEL", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId)
redis.call("HDEL", "$REDIS_KEY_COMPUTE_ID_TO_JOB_ID", computeJobId)
redis.call("HDEL", "$REDIS_KEY_COMPUTEJOB_WORKING_STATE", computeJobId)

$SNIPPET_PROCESS_PENDING
',

		SCRIPT_REMOVE_JOB =>
'
local jobId = ARGV[1]
local time = tonumber(ARGV[2])

local computeJobId = redis.call("HGET", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID", jobId)

$SNIPPET_REMOVE_JOB_RECORD

if computeJobId then
	${InstancePool.SNIPPET_REMOVE_JOB}
end
$SNIPPET_PROCESS_PENDING
',

		SCRIPT_REMOVE_COMPUTE_JOB =>
'
local computeJobId = ARGV[1]
local time = tonumber(ARGV[2])

local jobId = redis.call("HGET", "$REDIS_KEY_COMPUTE_ID_TO_JOB_ID", computeJobId)

$SNIPPET_REMOVE_JOB_RECORD

if computeJobId then
	${InstancePool.SNIPPET_REMOVE_JOB}
end
$SNIPPET_PROCESS_PENDING
',

		SCRIPT_REMOVE_ALL_JOB_DATA =>
'
local jobId = ARGV[1]
local status = redis.call("HGET", "$REDIS_KEY_STATUS", jobId)
if not status then
	return --Job already removed
end
if status ~= "${JobStatus.Finished}" then
	return {err="Job is not finished, but removeFinishedJobFromDatabase(jobId=" .. jobId .. ")"}
end
$SNIPPET_REMOVE_JOB_RECORD
',

		SCRIPT_GETSTATS =>
'
local jobId = ARGV[1]
$SNIPPET_GET_STATSOBJECT
return cjson.encode(stats)
',

		SCRIPT_JOB_STATUS =>//<JobStatusBlob>
'
local jobId = ARGV[1]
local statusBlob = cjson.decode(redis.call("HGET", "$REDIS_KEY_STATUS", jobId))
local status = statusBlob.JobStatus
local result = {status=status}
if status == "${JobStatus.Working}" then
	local computeJobId = redis.call("HGET", "${REDIS_KEY_JOB_ID_TO_COMPUTE_ID}", jobId)
	result.statusWorking = redis.call("HGET", "${REDIS_KEY_COMPUTEJOB_WORKING_STATE}", computeJobId)
end
return cjson.encode(result)
',

		SCRIPT_JOB_STATUSES =>//<Map<JobId,JobStatusBlob>>
'
local jobIds = redis.call("HKEYS", "$REDIS_KEY_STATUS")
local result = {}
for i,jobId in ipairs(jobIds) do
	local statusBlob = cjson.decode(redis.call("HGET", "$REDIS_KEY_STATUS", jobId))
	local status = statusBlob.JobStatus
	result[jobId] = {status=status}
	if status == "${JobStatus.Working}" then
		local computeJobId = redis.call("HGET", "${REDIS_KEY_JOB_ID_TO_COMPUTE_ID}", jobId)
		result[jobId].statusWorking = redis.call("HGET", "${REDIS_KEY_COMPUTEJOB_WORKING_STATE}", computeJobId)
	end
end
return cjson.encode(result)
',

			SCRIPT_TO_JSON =>
'
local result = {}

result.pending = redis.call("LRANGE", "$REDIS_KEY_PENDING", 0, -1)
local working = redis.call("ZRANGE", "$REDIS_KEY_WORKING", 0, -1, "withscores")
result.working = {}
for i=1,#working,2 do
	table.insert(result.working, {id=working[i], score=tonumber(working[i + 1])})
end

local computeJobIds = redis.call("HGETALL", "$REDIS_KEY_JOB_ID_TO_COMPUTE_ID")
result.computeJobIds = {}
result.jobIds = {}
for i=1,#computeJobIds,2 do
	result.computeJobIds[computeJobIds[i]] = computeJobIds[i + 1]
	result.jobIds[computeJobIds[i + 1]] = computeJobIds[i]
end

local workingStates = redis.call("HGETALL", "$REDIS_KEY_COMPUTEJOB_WORKING_STATE")
result.workingState = {}
for i=1,#workingStates,2 do
	result.workingState[workingStates[i]] = workingStates[i + 1]
end

local jobStatus = redis.call("HGETALL", "$REDIS_KEY_STATUS")
result.jobStatus = {}
for i=1,#jobStatus,2 do
	result.jobStatus[jobStatus[i]] = cjson.decode(jobStatus[i + 1])
end

local jobStats = redis.call("HGETALL", "$REDIS_KEY_STATS")
result.stats = {}
for i=1,#jobStats,2 do
	local stats = cmsgpack.unpack(jobStats[i + 1])
	result.stats[jobStats[i]] = stats
end

return cjson.encode(result)
',
	];
}

abstract Stats(Array<Float>)
{
	//!!!!! These are Lua indices, starting from 1, not zero
	inline public static var INDEX_ENQUEUE_TIME = 1;
	inline public static var INDEX_LAST_DEQUEUE_TIME = 2;
	inline public static var INDEX_DEQUEUE_COUNT = 3;
	inline public static var INDEX_LAST_REQUEUE_TIME = 4;
	inline public static var INDEX_REQUEUE_COUNT = 5;
	inline public static var INDEX_FINISH_TIME = 6;

	inline public function new()
	{
		this = [0, 0, 0, 0, 0, 0];
	}

	inline public function isFinished() :Bool
	{
		return this[INDEX_FINISH_TIME - 1] != 0;
	}

	public var enqueueTime(get, never) :Float;
	inline function get_enqueueTime() :Float
	{
		return this[INDEX_ENQUEUE_TIME - 1];
	}

	public var lastDequeueTime(get, never) :Float;
	inline function get_lastDequeueTime() :Float
	{
		return this[INDEX_LAST_DEQUEUE_TIME - 1];
	}

	public var dequeueCount(get, never) :Int;
	inline function get_dequeueCount() :Int
	{
		return Std.int(this[INDEX_DEQUEUE_COUNT - 1]);
	}

	public var lastRequeueTime(get, never) :Float;
	inline function get_lastRequeueTime() :Float
	{
		return this[INDEX_LAST_REQUEUE_TIME - 1];
	}

	public var requeueCount(get, never) :Int;
	inline function get_requeueCount() :Int
	{
		return Std.int(this[INDEX_REQUEUE_COUNT - 1]);
	}

	public var finishTime(get, never) :Float;
	inline function get_finishTime() :Float
	{
		return this[INDEX_FINISH_TIME - 1];
	}

	inline public function setEnqueueTime(?stamp :Float) :Stats
	{
		if (stamp == null) {
			stamp = Date.now().getTime();
		}
		this[INDEX_ENQUEUE_TIME - 1] = stamp;
		return this;
	}

	@:from
	inline static public function fromString (s: String) :Stats
	{
		try {
			var bytes = Bytes.ofString(s);
			var arr :Array<Float> = MsgPack.decode(bytes);
			return fromFloatArray(arr);
		} catch(err :Dynamic) {
			Log.error('Failed to parse msgpack string="$s"');
			return new Stats();
		}
	}

	@:from
	inline static public function fromFloatArray (arr: Array<Float>) :Stats
	{
		return cast arr;
	}

	@:to
	inline public function toString() :String
	{
		return Json.stringify(this);
	}

	@:to
	inline public function toJson() :TypedDynamicObject<String,Float>
	{
		var obj = {};
		Reflect.setField(obj, 'time_enqueued', enqueueTime);
		Reflect.setField(obj, 'time_last_dequeue', lastDequeueTime);
		Reflect.setField(obj, 'count_dequeue', dequeueCount);
		Reflect.setField(obj, 'time_last_requeue', lastRequeueTime);
		Reflect.setField(obj, 'count_requeue', requeueCount);
		Reflect.setField(obj, 'time_finished', finishTime);
		return obj;
	}

}

/*
 * Helper defintions and tools for dealing with a JSON
 * description of the system.
 */
typedef QueueJsonDump = {
	var pending :Array<JobId>;
	var working :Array<{id:JobId, score:Float}>;
	var computeJobIds :TypedDynamicObject<JobId, ComputeJobId>;
	var jobIds :TypedDynamicObject<ComputeJobId,JobId>;
	var jobStatus :TypedDynamicObject<JobId, JobStatusUpdate>;
	var stats :TypedDynamicObject<JobId, Stats>;
	var jobFinishedStatus :TypedDynamicObject<JobId, JobFinishedStatus>;
	var jobWorkingStatus :TypedDynamicObject<ComputeJobId, JobWorkingStatus>;
}

@:forward
abstract QueueJson(QueueJsonDump) from QueueJsonDump
{
	inline function new (d: QueueJsonDump)
		this = d;

	public var pending (get, never) :Array<JobId>;
	public var working (get, never) :Array<{id:JobId, score:Float}>;

	inline function get_pending() :Array<JobId>
	{
		if (this.pending == null || Reflect.fields(this.pending).length == 0) {
			return [];
		} else {
			return this.pending;
		}
	}

	inline function get_working() :Array<{id:JobId, score:Float}>
	{
		if (this.working == null || Reflect.fields(this.working).length == 0) {
			return [];
		} else {
			return this.working;
		}
	}

	inline public function getFinishedAndStatus(?max :Int = -1) :TypedDynamicObject<JobFinishedStatus,Array<JobId>>
	{
		if (this.jobStatus == null || Reflect.fields(this.jobStatus).length == 0) {
			return {};
		} else {
			var results :TypedDynamicObject<JobFinishedStatus,Array<JobId>> = {};
			var jobids = this.jobStatus.keys();
			jobids.sort(Reflect.compare);
			if (max > -1) {
				jobids = jobids.slice(0, max);
			}
			for (jobId in jobids) {
				var statusUpdate :JobStatusUpdate = this.jobStatus[jobId];
				if (statusUpdate.JobStatus == JobStatus.Finished) {
					var finishedStatus :String = statusUpdate.JobFinishedStatus;
					if (!results.exists(finishedStatus)) {
						results.set(finishedStatus, []);
					}
					results.get(finishedStatus).push(jobId);
				}
			}
			return results;
		}
	}

	inline public function getFinishedJobs() :Array<JobId>
	{
		if (this.jobStatus == null || Reflect.fields(this.jobStatus).length == 0) {
			return [];
		} else {
			var jobids = this.jobStatus.keys();
			jobids.sort(Reflect.compare);
			jobids = jobids.filter(function(jobId) {
				return this.jobStatus[jobId].JobStatus == JobStatus.Finished;
			});
			return jobids;
		}
	}

	inline public function isJobInQueue(jobId :JobId) :Bool
	{
		return pending.has(jobId) || working.exists(function(e) return e.id == jobId);
	}

	inline public function getComputeJobId(jobId :JobId) :ComputeJobId
	{
		return Reflect.field(this.computeJobIds, jobId);
	}

	inline public function getStats(jobId :JobId) :Stats
	{
		return Reflect.field(this.stats, jobId);
	}

	inline public function getJobId(computeJobId :ComputeJobId) :JobId
	{
		return Reflect.field(this.jobIds, computeJobId);
	}
}
