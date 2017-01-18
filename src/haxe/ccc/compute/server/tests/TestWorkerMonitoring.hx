package ccc.compute.server.tests;

import ccc.compute.workers.WorkerProviderPkgCloud;

import cloud.MachineMonitor;

import js.npm.PkgCloud;
import js.npm.RedisClient;
import js.npm.ssh2.Ssh;

import minject.Injector;

import util.SshTools;

class TestWorkerMonitoring extends haxe.unit.async.PromiseTest
{
	var _config :ServiceConfigurationWorkerProvider;
	@inject public var _injector :Injector;
	@inject public var _redis :RedisClient;

	public function new()
	{
		//Get the ServerConfig is available
		var serviceConfig = InitConfigTools.getConfig();
		if (serviceConfig != null) {
			_config = serviceConfig.providers[0];
		}
	}

	@timeout(1200000)//20min
	/**
	 * Parallelize these tests for speed
	 * @return [description]
	 */
	public function testWorkerMonitor() :Promise<Bool>
	{
		var promises = [_testWorkerDiskFull(), _testWorkerDockerMonitor()];

		return Promise.whenAll(promises)
			.then(function(results) {
				return !results.exists(function(e) return !e);
			});
	}

	/**
	 * A job is assigned to a worker, the worker is killed, then the job
	 * should be rescheduled (and not failed).
	 */
	@timeout(600000)//10m
	public function testJobOkWorkerOkAfterDockerDaemonReboot() :Promise<Bool>
	{
		var promise = new DeferredPromise();
		var provider :ccc.compute.workers.WorkerProviderPkgCloud = _injector.getValue(ccc.compute.workers.WorkerProvider);
		if (Type.getClass(provider) != WorkerProviderPkgCloud) {
			traceYellow('Cannot run test testJobOkWorkerOkAfterDockerDaemonReboot, it does not work on the local compute provider');
			return Promise.promise(true);
		}
		var serverHostRPCAPI = 'http://localhost:${SERVER_DEFAULT_PORT}${SERVER_RPC_URL}';
		var proxy = ServerTestTools.getProxy(serverHostRPCAPI);

		//Submit a long running job
		var jobId :JobId = null;
		var workerId :MachineId = null;
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ['sleep', '40'])
			.pipe(function(out) {
				jobId = out.jobId;
				//Reboot docker on the machine the job is on

				//First wait until it is assigned a worker, then get the worker id
				return PromiseTools.untilTrue(function() {
					return proxy.pending()
						.pipe(function(pending) {
							if (pending.has(jobId)) {
								return Promise.promise(false);
							} else {
								return proxy.status()
									.then(function(systemStatus :SystemStatus) {
										//Get the worker
										var worker = systemStatus.workers.find(function(w) {
											return w.jobs.exists(function(j) {
												return j.id == jobId;
											});
										});
										assertNotNull(worker);
										assertNotEquals(worker.id, workerId);
										workerId = worker.id;
										return true;
									});
							}
						});
				})
				.then(function(_) {
					return workerId;
				});
			})
			//Then restart the docker daemon on the worker
			.pipe(function(workerId) {
				return ccc.compute.server.InstancePool.getWorker(_redis, workerId)
					.pipe(function(worker) {
						return SshTools.execute(worker.ssh, "sudo systemctl restart docker.service");
					});
			})
			//The daemon will be restarted, but the job won't be
			.thenWait(400)
			//There should be no trace of the worker in the InstancePool
			// .pipe(function(_) {
			// 	return InstancePool.toJson(_redis)
			// 		.then(function(instancePoolJsonDump) {
			// 			instancePoolJsonDump.removed_record = null;
			// 			if (Json.stringify(instancePoolJsonDump).indexOf(workerId) != -1) {
			// 				traceRed(Json.stringify(instancePoolJsonDump, null, '\t'));
			// 			}
			// 			assertTrue(Json.stringify(instancePoolJsonDump).indexOf(workerId) == -1);
			// 			return true;
			// 		});
			// })
			.pipe(function(_) {
				return PromiseTools.untilTrue(function() {
					return proxy.pending()
						.pipe(function(pending) {
							if (pending.has(jobId)) {
								return Promise.promise(false);
							} else {
								return proxy.status()
									.then(function(systemStatus :SystemStatus) {
										//Get the worker
										traceCyan(systemStatus);
										// var worker = systemStatus.workers.find(function(w) {
										// 	return w.jobs.exists(function(j) {
										// 		return j.id == jobId;
										// 	});
										// });
										// assertNotNull(worker);
										// assertNotEquals(worker.id, workerId);
										return true;
									});
							}
						});
				});
			})
			.thenTrue();
	}

	/**
	 * A job is assigned to a worker, the worker is killed, then the job
	 * should be rescheduled (and not failed).
	 */
	@timeout(600000)//10m
	public function testJobRescheduledAfterWorkerFailure() :Promise<Bool>
	{
		var promise = new DeferredPromise();
		var provider :ccc.compute.workers.WorkerProviderPkgCloud = _injector.getValue(ccc.compute.workers.WorkerProvider);
		if (Type.getClass(provider) != WorkerProviderPkgCloud) {
			traceYellow('Cannot run test testJobRescheduledAfterWorkerFailure, it does not work on the local compute provider');
			return Promise.promise(true);
		}
		var serverHostRPCAPI = 'http://localhost:${SERVER_DEFAULT_PORT}${SERVER_RPC_URL}';
		var proxy = ServerTestTools.getProxy(serverHostRPCAPI);

		//Submit a long running job
		var jobId :JobId = null;
		var workerId :MachineId = null;
		return proxy.submitJob(DOCKER_IMAGE_DEFAULT, ['sleep', '40'])
			.pipe(function(out) {
				jobId = out.jobId;
				//Kill the machine the job is on

				//First wait until it is assigned a worker, then get the worker id
				return PromiseTools.untilTrue(function() {
					return proxy.pending()
						.pipe(function(pending) {
							if (pending.has(jobId)) {
								return Promise.promise(false);
							} else {
								return proxy.status()
									.then(function(systemStatus :SystemStatus) {
										//Get the worker
										var worker = systemStatus.workers.find(function(w) {
											return w.jobs.exists(function(j) {
												return j.id == jobId;
											});
										});
										assertNotNull(worker);
										assertNotEquals(worker.id, workerId);
										workerId = worker.id;
										return true;
									});
							}
						});
				})
				.then(function(_) {
					return workerId;
				});
			})
			//Then kill the worker
			.pipe(function(workerId) {
				return proxy.workerRemove(workerId);
			})
			.thenWait(400)
			//There should be no trace of the worker in the InstancePool
			.pipe(function(_) {
				return InstancePool.toJson(_redis)
					.then(function(instancePoolJsonDump) {
						instancePoolJsonDump.removed_record = null;
						if (Json.stringify(instancePoolJsonDump).indexOf(workerId) != -1) {
							traceRed(Json.stringify(instancePoolJsonDump, null, '\t'));
						}
						assertTrue(Json.stringify(instancePoolJsonDump).indexOf(workerId) == -1);
						return true;
					});
			})
			.pipe(function(_) {
				return PromiseTools.untilTrue(function() {
					return proxy.pending()
						.pipe(function(pending) {
							if (pending.has(jobId)) {
								return Promise.promise(false);
							} else {
								return proxy.status()
									.then(function(systemStatus :SystemStatus) {
										//Get the worker
										var worker = systemStatus.workers.find(function(w) {
											return w.jobs.exists(function(j) {
												return j.id == jobId;
											});
										});
										assertNotNull(worker);
										assertNotEquals(worker.id, workerId);
										return true;
									});
							}
						});
				});
			})
			.thenTrue();
	}

	@timeout(10000)//10s
	/**
	 * Workers that do not exist should fail correctly
	 */
	public function testWorkerMissingOnStartup() :Promise<Bool>
	{
		var promise = new DeferredPromise();
		var monitor = new MachineMonitor()
			.monitorDocker({host: '70.87.168.45', port: 2375, protocol: 'http'});
		monitor.status.then(function(status) {
			switch(status) {
				case Connecting:
				case OK:
					if (promise != null) {
						promise.boundPromise.reject('Wrong status=${status}, should never be OK since the machine does not exist');
						promise = null;
					}
				case CriticalFailure(failure):
					assertEquals(failure, MachineFailureType.DockerConnectionLost);
					if (promise != null) {
						promise.resolve(true);
						promise = null;
					}
			}
		});
		return promise.boundPromise;
	}

	/**
	 * Creates a fake worker, monitors it, and then proceeds to
	 * fill up the disk. It should register as failed when the
	 * disk reaches a given capacity.
	 */
	@timeout(1200000)//20min
	//This test can run in parallel to others
	public function _testWorkerDockerMonitor() :Promise<Bool>
	{
		if (_config == null || _config.type != ServiceWorkerProviderType.pkgcloud) {
			traceYellow('Cannot run ${Type.getClassName(Type.getClass(this)).split('.').pop()}.testWorkerDockerMonitor: no configuration for a real cloud provider');
			return Promise.promise(true);
		} else if (!_config.machines.exists('test')) {
			traceYellow('Cannot run ${Type.getClassName(Type.getClass(this)).split('.').pop()}.testWorkerDockerMonitor: missing worker definition "test"');
			return Promise.promise(true);
		} else {
			return internalTestWorkerMonitorDockerPing(_config);
		}
	}

	@timeout(1200000)//20min
	//This test can run in parallel to others
	public function _testWorkerDiskFull() :Promise<Bool>
	{
		if (_config == null || _config.type != ServiceWorkerProviderType.pkgcloud) {
			traceYellow('Cannot run ${Type.getClassName(Type.getClass(this)).split('.').pop()}.testWorkerDiskFull: no configuration for a real cloud provider');
			return Promise.promise(true);
		} else if (!_config.machines.exists('test')) {
			traceYellow('Cannot run ${Type.getClassName(Type.getClass(this)).split('.').pop()}.testWorkerDiskFull: missing worker definition "test"');
			return Promise.promise(true);
		} else {
			return internalTestWorkerMonitorDiskCapacity(_config);
		}
	}

	static function internalTestWorkerMonitorDockerPing(config :ServiceConfigurationWorkerProvider) :Promise<Bool>
	{
		var machineType = 'test';
		var monitor :MachineMonitor;
		var instanceDef :InstanceDefinition;

		return Promise.promise(true)
			.pipe(function(_) {
				return WorkerProviderPkgCloud.createInstance(config, machineType);
			})
			.pipe(function(def) {
				instanceDef = def;
				var promise = new DeferredPromise();
				monitor = new MachineMonitor()
					.monitorDocker(instanceDef.docker, 1000, 3, 1000);
				monitor.status.then(function(status) {
					switch(status) {
						case Connecting:
						case OK:
							if (promise != null) {
								promise.resolve(status);
								promise = null;
							}
						case CriticalFailure(failure):
							if (promise != null) {
								promise.boundPromise.reject(failure);
								promise = null;
							}
					}
				});
				return promise.boundPromise;
			})
			.pipe(function(status) {
				//Now kill the machine, and the listen for the failure
				var promise = new DeferredPromise<Bool>();
				var gotFailure = false;
				var shutdown = false;
				monitor.status.then(function(state) {
					switch(state) {
						case Connecting,OK:
						case CriticalFailure(failureType):
							switch(failureType) {
								case DockerConnectionLost:
									if (promise != null) {
										gotFailure = true;
										promise.resolve(true);
										promise = null;
									}
								default:
									if (promise != null) {
										promise.boundPromise.reject('Wrong failure type: $failureType');
										promise = null;
									}
							}
					}
				});
				WorkerProviderPkgCloud.destroyCloudInstance(config, instanceDef.id)
					.then(function(_) {
						shutdown = true;
						js.Node.setTimeout(function() {
							if (!gotFailure && promise != null) {
								promise.boundPromise.reject('Timeout waiting on induced docker failure, failed to detect it');
								promise = null;
							}
						}, 30000);//30s, plenty of time
					});

				return promise.boundPromise;
			})
			.errorPipe(function(err) {
				traceRed(err);
				return WorkerProviderPkgCloud.destroyCloudInstance(config, instanceDef.id)
					.then(function(_) {
						return false;
					})
					.errorPipe(function(err) {
						traceRed(err);
						return Promise.promise(false);
					});
			});
	}

	static function internalTestWorkerMonitorDiskCapacity(config :ServiceConfigurationWorkerProvider) :Promise<Bool>
	{
		var machineType = 'test';
		var monitor :MachineMonitor;
		var instanceDef :InstanceDefinition;

		return Promise.promise(true)
			.pipe(function(_) {
				return WorkerProviderPkgCloud.createInstance(config, machineType, null);
			})
			.pipe(function(def) {
				instanceDef = def;
				var promise = new DeferredPromise();
				monitor = new MachineMonitor()
					.monitorDiskSpace(instanceDef.ssh, 0.2, 1000, 3, 1000);
				monitor.status.then(function(status) {
					switch(status) {
						case Connecting:
						case OK:
							if (promise != null) {
								promise.resolve(status);
								promise = null;
							}
						case CriticalFailure(failure):
							if (promise != null) {
								promise.boundPromise .reject(failure);
								promise = null;
							}
					}
				});
				return promise.boundPromise;
			})
			.pipe(function(status) {
				//Now fill up disk space, and the listen for the failure
				var promise = new DeferredPromise<Bool>();
				var gotFailure = false;
				// var shutdown = false;
				monitor.status.then(function(state) {
					switch(state) {
						case Connecting,OK:
						case CriticalFailure(failureType):
							switch(failureType) {
								case DiskCapacityCritical:
									if (promise != null) {
										gotFailure = true;
										promise.resolve(true);
										promise = null;
									}
								default:
									if (promise != null) {
										promise.boundPromise.reject('Wrong failure type: $failureType');
										promise = null;
									}
							}
					}
				});
				var addSpace = null;
				var addSpaceCount = 1;
				addSpace = function() {
					createFile(instanceDef.ssh, '/blob${addSpaceCount++}', 1000)
						.then(function(out) {
							if (!gotFailure && promise != null) {
								addSpace();
							}
						});
				}
				addSpace();

				return promise.boundPromise
					//But always destroy this machine when the test is done
					.pipe(function(result) {
						return WorkerProviderPkgCloud.destroyCloudInstance(config, instanceDef.id)
							.then(function(_) {
								return result;
							})
							.errorPipe(function(err) {
								traceRed(err);
								return Promise.promise(result);
							});
					});
			})
			.errorPipe(function(err) {
				traceRed(err);
				return WorkerProviderPkgCloud.destroyCloudInstance(config, instanceDef.id)
					.then(function(_) {
						return false;
					})
					.errorPipe(function(err) {
						traceRed(err);
						return Promise.promise(false);
					});
			});
	}

	static function createFile(ssh :ConnectOptions, path :String, sizeMb :Int = 1) :Promise<Bool>
	{
		return SshTools.execute(ssh, 'sudo dd if=/dev/zero of=$path count=$sizeMb bs=1048576', 1)
			.then(function(out) {
				return out.code == 0;
			});
	}
}