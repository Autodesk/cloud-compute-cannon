package ccc.compute.server.execution.routes;

import haxe.Resource;

import js.npm.RedisClient;
import js.npm.docker.Docker;
import js.npm.redis.RedisLuaTools;

import util.DockerTools;
import util.DockerUrl;
import util.DockerRegistryTools;
import util.DateFormatTools;

/**
 * Server API methods
 */
class ServerCommands
{
	/** For debugging */
	public static function traceStatus() :Promise<Bool>
	{
		return status()
			.then(function(statusBlob) {
				traceMagenta(Json.stringify(statusBlob, null, "  "));
				return true;
			});
	}

	public static function status() :Promise<SystemStatus>
	{
		return Promise.promise(null);
		// var workerJson :InstancePoolJson = null;
		// var jobsJson :QueueJson = null;
		// var workerJsonRaw :Dynamic = null;
		// return Promise.promise(true)
		// 	.pipe(function(_) {
		// 		return Promise.whenAll(
		// 			[
		// 				InstancePool.toJson(redis)
		// 					.then(function(out) {
		// 						workerJson = out;
		// 						return true;
		// 					}),
		// 				ComputeQueue.toJson(redis)
		// 					.then(function(out) {
		// 						jobsJson = out;
		// 						return true;
		// 					}),
		// 				InstancePool.toRawJson(redis)
		// 					.then(function(out) {
		// 						workerJsonRaw = out;
		// 						return true;
		// 					})
		// 			]);
		// 	})
		// 	.then(function(_) {
		// 		var now = Date.now();
		// 		var result = {
		// 			now: DateFormatTools.getFormattedDate(now.getTime()),
		// 			pendingCount: jobsJson.pending.length,
		// 			pendingTop5: jobsJson.pending.slice(0, 5),
		// 			workers: workerJson.getMachines().map(function(m :JsonDumpInstance) {
		// 				var timeout :String = null;
		// 				if (workerJson.timeouts.exists(m.id)) {
		// 					var timeoutDate = Date.fromTime(workerJson.getTimeout(m.id));
		// 					timeout = DateFormatTools.getShortStringOfDateDiff(timeoutDate, now);
		// 				}
		// 				return {
		// 					id :m.id,
		// 					jobs: m.jobs != null ? m.jobs.map(function(computeJobId) {
		// 						var jobId = jobsJson.getJobId(computeJobId);
		// 						var stats = jobsJson.getStats(jobId);
		// 						var enqueued = Date.fromTime(stats.enqueueTime);
		// 						var dequeued = Date.fromTime(stats.lastDequeueTime);
		// 						return {
		// 							id: jobId,
		// 							enqueued: enqueued.toString(),
		// 							started: dequeued.toString(),
		// 							duration: DateFormatTools.getShortStringOfDateDiff(dequeued, now)
		// 						}
		// 					}) : [],
		// 					cpus: '${workerJson.getAvailableCpus(m.id)}/${workerJson.getTotalCpus(m.id)}',
		// 					timeout: timeout
		// 				};
		// 			}),
		// 			finishedCount: jobsJson.getFinishedJobs().length,
		// 			finishedTop5: jobsJson.getFinishedAndStatus(5),
		// 			// workerJson: workerJson,
		// 			// workerJsonRaw: workerJsonRaw
		// 		};
		// 		return result;
		// 	})
		// 	.pipe(function(result) {
		// 		var promises = workerJson.getMachines().map(
		// 			function(m) {
		// 				return InstancePool.getWorker(redis, m.id)
		// 					.pipe(function(workerDef) {
		// 						if (workerDef.ssh != null) {
		// 							return cloud.MachineMonitor.getDiskUsage(workerDef.ssh)
		// 								.then(function(usage) {
		// 									result.workers.iter(function(blob) {
		// 										if (blob.id == m.id) {
		// 											Reflect.setField(blob, 'disk', usage);
		// 										}
		// 									});
		// 									return true;
		// 								})
		// 								.errorPipe(function(err) {
		// 									Log.error({error:err, message:'Failed to get disk space for worker=${m.id}'});
		// 									return Promise.promise(false);
		// 								});
		// 						} else {
		// 							return Promise.promise(true);
		// 						}
		// 					});
		// 			});
		// 		return Promise.whenAll(promises)
		// 			.then(function(_) {
		// 				return result;
		// 			});
		// 	});
	}

	public static function version() :ServerVersionBlob
	{
		if (_versionBlob == null) {
			_versionBlob = versionInternal();
		}
		return _versionBlob;
	}

	static var _versionBlob :ServerVersionBlob;
	static function versionInternal()
	{
		var date = util.MacroUtils.compilationTime();
		var haxeCompilerVersion = Version.getHaxeCompilerVersion();
		var customVersion = null;
		try {
			customVersion = Fs.readFileSync('VERSION', {encoding:'utf8'}).trim();
		} catch(ignored :Dynamic) {
			customVersion = null;
		}
		var npmPackageVersion = null;
		try {
			npmPackageVersion = Json.parse(Resource.getString('package.json')).version;
		}
		var gitSha = null;
		try {
			gitSha = Version.getGitCommitHash().substr(0,8);
		} catch(e :Dynamic) {}

		//Single per instance id.
		var instanceVersion :String = null;
		try {
			instanceVersion = Fs.readFileSync('INSTANCE_VERSION', {encoding:'utf8'});
		} catch(ignored :Dynamic) {
			instanceVersion = js.npm.shortid.ShortId.generate();
			Fs.writeFileSync('INSTANCE_VERSION', instanceVersion, {encoding:'utf8'});
		}

		return {npm:npmPackageVersion, git:gitSha, compiler:haxeCompilerVersion, VERSION:customVersion, instance:instanceVersion, compile_time:date};
	}

	// public static function serverReset(redis :RedisClient, fs :ServiceStorage) :Promise<Bool>
	// {
	// 	return return ComputeQueue.getAllJobIds(redis)
	// 		.pipe(function(jobIds :Array<JobId>) {
	// 			return Promise.whenAll(jobIds.map(function(jobId) {
	// 				return ComputeQueue.getJob(redis, jobId)
	// 					.pipe(function(job :DockerJobDefinition) {
	// 						return DockerJobTools.deleteJobRemoteData(job, fs);
	// 					});
	// 			}));
	// 		})
	// 		.pipe(function(_) {
	// 			return hardStopAndDeleteAllJobs(redis);
	// 		});
	// }

}