package ccc.compute.server.execution.routes;

import haxe.Resource;

import js.npm.docker.Docker;
import js.npm.redis.RedisClient;
import js.npm.redis.RedisLuaTools;

import util.DockerTools;
import util.DockerUrl;
import util.DockerRegistryTools;
import util.DateFormatTools;

/**
 * Server API methods
 */
class WorkerCommands
{
	public static function statusWorkers(redis :RedisClient) :Promise<Dynamic>
	{
		var workerJson :InstancePoolJson = null;
		var workerJsonRaw :Dynamic = null;
		return Promise.promise(true)
			.pipe(function(_) {
				return Promise.whenAll(
					[
						InstancePool.toJson(redis)
							.then(function(out) {
								workerJson = out;
								return true;
							}),
						InstancePool.toRawJson(redis)
							.then(function(out) {
								workerJsonRaw = out;
								return true;
							})
					]);
			})
			.then(function(_) {
				var now = Date.now();
				var result = {
					now: DateFormatTools.getFormattedDate(now.getTime()),
					workers: workerJson.getMachines().map(function(m :JsonDumpInstance) {
						var timeout :String = null;
						if (workerJson.timeouts.exists(m.id)) {
							var timeoutDate = Date.fromTime(workerJson.getTimeout(m.id));
							timeout = DateFormatTools.getShortStringOfDateDiff(timeoutDate, now);
						}
						return {
							id :m.id,
							jobs: m.jobs != null ? m.jobs.length : 0,
							cpus: '${workerJson.getAvailableCpus(m.id)}/${workerJson.getTotalCpus(m.id)}',
							timeout: timeout,
							status: workerJson.status.get(m.id)
						};
					}),
					removed: workerJson.getRemovedMachines()
					// raw: workerJsonRaw
				};
				return result;
			})
			.pipe(function(result) {
				var promises = workerJson.getMachines().map(
					function(m) {
						return InstancePool.getWorker(redis, m.id)
							.pipe(function(workerDef) {
								if (workerDef.ssh != null) {
									return cloud.MachineMonitor.getDiskUsage(workerDef.ssh)
										.then(function(usage) {
											result.workers.iter(function(blob) {
												if (blob.id == m.id) {
													Reflect.setField(blob, 'disk', usage);
												}
											});
											return true;
										})
										.errorPipe(function(err) {
											Log.error({error:err, message:'Failed to get disk space for worker=${m.id}'});
											return Promise.promise(false);
										});
								} else {
									return Promise.promise(true);
								}
							});
					});
				return Promise.whenAll(promises)
					.then(function(_) {
						return result;
					});
			});
	}

}