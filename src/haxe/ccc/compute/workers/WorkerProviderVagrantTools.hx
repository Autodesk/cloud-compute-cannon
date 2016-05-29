package ccc.compute.workers;

import haxe.Json;
import haxe.Resource;

import js.Node;
import js.node.Path;
import js.node.Fs;

import js.npm.Docker;
import js.npm.FsExtended;
import js.npm.FsPromises;
import js.npm.RedisClient;
import js.npm.Ssh;
import js.npm.Vagrant;

import promhx.Promise;
import promhx.deferred.DeferredPromise;
import promhx.RedisPromises;

import ccc.compute.ComputeTools;
import ccc.compute.InstancePool;
import ccc.compute.Definitions;
import ccc.compute.workers.VagrantTools;

import util.SshTools;
import util.streams.StdStreams;

import t9.abstracts.net.*;

using StringTools;
using ccc.compute.ComputeTools;
using promhx.PromiseTools;
using util.MapTools;
using Lambda;


typedef VagrantStatus = {
	var id :MachineId;
	var path :VagrantPath;
	var status :VagrantMachineStatus;
}

/**
 */
class WorkerProviderVagrantTools
{
	public static var MACHINE_PREFIX = 'machine__';
	static var IP_ADDRESS_BASE = '192.168.50.';
	static var START_IP_BIT = 100;
	static var MAX_WORKERS = 10;
	public static var CPUS_PER_MACHINE = 2;
	inline public static var ID = 'vagrant';
	inline public static var CHANNEL_JOB_ADDED = '${InstancePool.REDIS_KEY_WORKER_POOLS_CHANNEL_PREFIX}${ID}';
	inline static var VAGRANT_PREFIX = '${InstancePool.REDIS_COMPUTE_POOL_PREFIX}${ID}${Constants.SEP}';
	inline static var REDIS_IP_ADDRESS_POOL = '${VAGRANT_PREFIX}ip_address_pool';
	inline static var REDIS_DATA = '${VAGRANT_PREFIX}data';
	inline static var REDIS_MACHINE_TO_DIR = '${VAGRANT_PREFIX}machine_dirs';
	inline static var REDIS_TARGET = 'target';

	public static function removeMachineFromPool(redis :RedisClient, path :VagrantPath) :Promise<Bool>
	{
		var id :MachineId = path.getMachineId();
		var ip = path.getIp();

		return Promise.promise(true)
			.pipe(function(_) {
				return RedisPromises.hdel(redis, REDIS_MACHINE_TO_DIR, id);
			})
			.pipe(function(_) {
				return returnIpAddress(redis, ip);
			})
			.pipe(function(_) {
				return InstancePool.removeInstance(redis, id)
					.thenTrue();
			});
	}
	/**
	 * Checks if machines that are marked for removal have no running jobs and
	 * then destroy them.
	 * @param  redis    :RedisClient        [description]
	 * @param  rootPath :String             [description]
	 * @param  ?streams :StdStreams [description]
	 * @return          [description]
	 */
	static function XXcleanup(redis :RedisClient, rootPath :String, ?streams :StdStreams) :Promise<Bool>
	{
		var ip;
		return InstancePool.removeInstances(redis, ID)
			.pipe(function(machineIds :Array<MachineId>) {
				machineIds = machineIds == null || Reflect.fields(machineIds).length == 0 ? [] : machineIds;
				var promises: Array<Promise<Bool>> = machineIds.map(function(id :MachineId) {
					return RedisPromises.hget(redis, REDIS_MACHINE_TO_DIR, id)
						.pipe(function(path :String) {
							if (path != null) {
									ip = getIpFromPath(path);
									Log.info('Removing expired machine=$id path=$path ip=$ip');
									return VagrantTools.remove(path, true, streams);
							} else {
								Log.error('No path for id=$id');
								return Promise.promise(true);
							}
						})
						.pipe(function(_) {
							if (ip != null) {
								return returnIpAddress(redis, ip);
							} else {
								return Promise.promise(0);
							}
						})
						.pipe(function(_) {
							return RedisPromises.hdel(redis, REDIS_MACHINE_TO_DIR, id);
						})
						.pipe(function(_) {
							return InstancePool.removeInstance(redis, id)
								.thenTrue();
						});
				});
				return Promise.whenAll(promises);
			})
			.thenTrue();
	}

	public static function addExistingMachine(redis :RedisClient, path :VagrantPath, registryHost :Host, ?streams :StdStreams) :Promise<WorkerDefinition>
	{
		return addMachineInternal(redis, path, registryHost);
	}

	public static function addMachine(redis :RedisClient, rootPath :String, registryHost :Host, ?streams :StdStreams) :Promise<WorkerDefinition>
	{
		return getNextIpAddress(redis)
			.pipe(function(ip) {
				var vagrantPath = VagrantPath.from(ComputeTools.createUniqueId(), ip);
				var path = Path.join(rootPath, vagrantPath);
				FsExtended.ensureDirSync(path);
				return addMachineInternal(redis, new VagrantPath(path), registryHost, streams);
			});
	}

	static function addMachineInternal(redis :RedisClient, path :VagrantPath, registryHost :Host, ?streams :StdStreams) :Promise<WorkerDefinition>
	{
		var ip :IP = path.getIp();
		var id = path.getMachineId();
		var machineDef :WorkerDefinition;
		var machineParams = {cpus:CPUS_PER_MACHINE, memory:0};
		return Promise.promise(true)
			.pipe(function(_) {
				return RedisPromises.hset(redis, REDIS_MACHINE_TO_DIR, id, path.removeBasePath());
			})
			.pipe(function(_) {
				return ensureWorkerBox(path, ip, registryHost, streams);
			})
			.pipe(function(_) {
				return getWorkerDefinition(path);
			})
			.pipe(function(def) {
				machineDef = def;
				Assert.notNull(def);
				Assert.notNull(def.ssh);
				Assert.notNull(def.ssh.host, '$path failed to return a host value $def');
				Assert.that(def.ssh.host != '', '$path failed to return a host value $def');
				//Update the machine definition
				return InstancePool.addInstance(redis, ID, machineDef, machineParams, MachineStatus.Available);
			})
			.pipe(function(_) {
				return ComputeQueue.processPending(redis);
			})
			.then(function(_) {
				return machineDef;
			})
			.errorPipe(function(err) {
				//Add the address back
				Log.error('Returning ip=$ip back to the pool, removing machine in DB and disk because of the error=$err');
				returnIpAddress(redis, ip);
				VagrantTools.remove(path, true, streams);
				InstancePool.removeInstance(redis, id);
				//and rethrow the error
				throw err;
			});
	}

	public static function getTarget(redis :RedisClient) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		redis.hget(REDIS_DATA, REDIS_TARGET, promise.cb2);
		return promise
			.then(function(val) {
				return Std.parseInt(val + '');
			});
	}

	public static function setTarget(redis :RedisClient) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		redis.hget(REDIS_DATA, REDIS_TARGET, promise.cb2);
		return promise
			.then(function(val) {
				return Std.parseInt(val + '');
			});
	}

	public static function ensureWorkerBox(path :VagrantPath, ipAddress :String, registryHost :Host, ?streams :StdStreams) :Promise<VagrantMachine>
	{
		Assert.notNull(path);
		Assert.notNull(ipAddress);
		FsExtended.ensureDirSync(path);
		var vagrantFilePath = Path.join(path, 'Vagrantfile');
		var exists = false;
		try {
			var stats = Fs.statSync(vagrantFilePath);
			exists = stats.isDirectory();
		} catch (err :Dynamic) {}

		if (!exists) {
			//Don't just copy the whole directory because this
			//could overwrite an existing .vagrant folder
			//Write the vagrant file with some parameters
			Fs.writeFileSync(vagrantFilePath,
				new haxe.Template(Resource.getString('etc/vagrant/coreos/Vagrantfile.template'))
					.execute({name:Path.basename(path), ip:ipAddress}));
		}
		return VagrantTools.getMachineStatus(path)
			.pipe(function(status) {
				var machine;
				switch(status.status) {
					case NotCreated:
						//Build the machine
						return VagrantTools.ensureVagrantBoxRunning(path, streams)
							.pipe(function(vagrantMachine) {
								machine = vagrantMachine;
								return getSshConfig(path);
							})
							.pipe(function(sshConfig) {
								return WorkerProviderTools.setupCoreOS(sshConfig);
							})
							.then(function(_) {
								return machine;
							});
					case PowerOff:
						//Build the machine
						return VagrantTools.ensureVagrantBoxRunning(path, streams)
							.pipe(function(vagrantMachine) {
								machine = vagrantMachine;
								return getSshConfig(path);
							})
							.pipe(function(sshConfig) {
								return WorkerProviderTools.setupCoreOS(sshConfig);
							})
							.then(function(_) {
								return machine;
							});
					case Running:
						return Promise.promise(VagrantTools.getMachine(path));
					case Aborted:
						//Remove, then try again. Circular if it keeps aborting.
						Log.info('Vagrant status aborted, removing and retrying');
						return VagrantTools.remove(path, true, streams)
							.pipe(function(_) {
								return ensureWorkerBox(path, ipAddress, registryHost, streams);
							});
					case Saved:
						//Remove, then try again. Circular if it keeps aborting.
						Log.info('Vagrant status saved, removing and retrying');
						return VagrantTools.remove(path, true, streams)
							.pipe(function(_) {
								return ensureWorkerBox(path, ipAddress, registryHost, streams);
							});
					default:
						throw 'Unhandled status ${status.status}';
				}
			});
	}

	public static function getDockerConfig(path :VagrantPath) :Promise<ConstructorOpts>
	{
		var ssh;
		var sshConfig;
		return getSshConfig(path)
			.then(function(config :ConnectOptions) {
				var dockerDef :ConstructorOpts = {
					host: config.host,
					port: 2375,
					protocol: 'http'
				};
				return dockerDef;
			});
	}

	public static function getSshConfig(path :VagrantPath) :Promise<ConnectOptions>
	{
		var promise = new promhx.deferred.DeferredPromise();
		var machine = VagrantTools.getMachine(path);
		machine.sshConfig(function(err, config) {
			if (err != null) {
				Log.error(err);
				promise.boundPromise.reject(err);
				return;
			}
			var def :ConnectOptions = {
				host: config.hostname,
				port: Std.parseInt(config.port + ''),
				username: config.user,
				privateKey: Fs.readFileSync(config.private_key.replace('"', ''), {encoding:'utf8'})
			}
			SshTools.execute(def, "ip address show eth1 | grep 'inet ' | sed -e 's/^.*inet //' -e 's/\\/.*$//'")
				.then(function(result) {
					def.host = result.stdout.trim();
					def.port = 22;
					if (def.host == null || def.host == '') {
						throw 'Failed to get host from vagrant machine $path config.hostname=${config.hostname} def=${def}';
					}
					promise.resolve(def);
				})
				.catchError(function(err) {
					promise.boundPromise.reject(err);
				});
		});
		return promise.boundPromise;
	}

	public static function getWorkerDefinition(path :VagrantPath) :Promise<WorkerDefinition>
	{
		return getSshConfig(path)
			.then(function(config) {
				var base = Path.basename(path);
				var id = base.split('__')[1];
				var worker :WorkerDefinition = {
					id: id,
					hostPublic: new HostName(config.host),
					hostPrivate: new HostName(config.host),
					ssh: config,
					docker: {
						host: config.host,
						port: 2375,
						protocol: 'http'
					}
				};
				return worker;
			});
	}

	public static function XXsyncCurrentMachinesWithRedis(redis :RedisClient, rootPath :String, ?streams :StdStreams) :Promise<Bool>
	{
		var instancesInDb :Array<StatusResult>;
		var actualVagrantBoxes :Array<String>;

		return RedisPromises.del(redis, REDIS_IP_ADDRESS_POOL)
			.pipe(function(_) {
				return InstancePool.getInstancesInPool(redis, ID);
			})

			.pipe(function(result :Array<StatusResult>) {
				instancesInDb = result;
				actualVagrantBoxes = getVagrantBoxes(rootPath);
				// actualVagrantBoxes = actualVagrantBoxes.map(function(s) return Path.join(rootPath, s));
				var promises = new Array<Promise<Dynamic>>();

				var vagrantMachineIds = actualVagrantBoxes.map(function(p) return new VagrantPath(p).getMachineId()).array().createStringMapi(actualVagrantBoxes);
				var promises = new Array<Promise<Dynamic>>();
				//Remove entries in the db that don't actually exist
				for (dbWorker in instancesInDb) {
					if (!vagrantMachineIds.exists(dbWorker.id)) {
						Log.info('Redis worker entry found but does not exist in vagrant, removing id=${dbWorker.id}');
						promises.push(InstancePool.removeInstance(redis, dbWorker.id));
					}
				}
				//Add vagrant instances to redis
				for (vagrantId in vagrantMachineIds.keys()) {
					if (!instancesInDb.exists(function(e) return e.id == vagrantId)) {
						Log.info('Existing vagrant worker, adding to db=${vagrantMachineIds.get(vagrantId)}');
						var vagrantInstancePath :VagrantPath = vagrantMachineIds.get(vagrantId);
						var promise = getWorkerDefinition(vagrantInstancePath)
							.pipe(function(workerDef) {
								return InstancePool.addInstance(redis, ID, workerDef, {cpus:CPUS_PER_MACHINE, memory:0})//TODO: get the cpus from the Vagrant info
									.pipe(function(_) {
										return RedisPromises.hset(redis, REDIS_MACHINE_TO_DIR, workerDef.id, vagrantInstancePath);
									})
									.thenTrue();
							})
							.errorPipe(function(err) {
								Log.error(err);
								Log.error('Cleaning up vagrant instance from file system and db');
								var cleanupPromises = new Array<Promise<Dynamic>>();
								//Remove from db just in case it was addeed during error
								cleanupPromises.push(InstancePool.removeInstance(redis, vagrantId));
								cleanupPromises.push(VagrantTools.remove(vagrantInstancePath, true, streams));
								return Promise.whenAll(cleanupPromises)
									.thenTrue();
							});
						promises.push(promise);
					}
				}
				return Promise.whenAll(promises);
			})
			.pipe(function(_) {
				//Now get the remaining vagrant instances, and add the remaining IP addresses to a global pool
				var vagrantIpAddresses = getVagrantBoxes(rootPath).map(function(p) return new VagrantPath(p).getIp().toString()).array();
				var set = Set.createString(vagrantIpAddresses);
				var remainingIpAddress = [];
				for (i in 0...MAX_WORKERS) {
					var ip = IP_ADDRESS_BASE + (START_IP_BIT + i);
					if (!set.has(ip)) {
						remainingIpAddress.push(ip);
					}
				}
				if (remainingIpAddress.length > 0) {
					var promise = new promhx.deferred.DeferredPromise();
					var lua = 'redis.call("LPUSH", "$REDIS_IP_ADDRESS_POOL", "' + remainingIpAddress.join('", "') + '")';
					var command :Array<Dynamic> = [lua, 0];
					redis.eval(command, function(err, out) {
						if (err != null) {
							Log.error(err);
							promise.boundPromise.reject(err);
							return;
						}
						promise.resolve(out);
					});
					return promise.boundPromise.thenTrue();
				} else {
					return Promise.promise(true);
				}
			})
			.thenTrue();
	}

	public static function addIpAddressToPool(redis :RedisClient, rootPath :String) :Promise<Bool>
	{
		var instancesInDb :Array<StatusResult>;
		var actualVagrantBoxes :Array<String>;
		return RedisPromises.del(redis, REDIS_IP_ADDRESS_POOL)
			.pipe(function(_) {
				//Now get the remaining vagrant instances, and add the remaining IP addresses to a global pool
				var vagrantIpAddresses = getVagrantBoxes(rootPath).map(function(p) return new VagrantPath(p).getIp().toString()).array();
				var set = Set.createString(vagrantIpAddresses);
				var remainingIpAddress = [];
				for (i in 0...MAX_WORKERS) {
					var ip = IP_ADDRESS_BASE + (START_IP_BIT + i);
					if (!set.has(ip)) {
						remainingIpAddress.push(ip);
					}
				}
				if (remainingIpAddress.length > 0) {
					var promise = new promhx.deferred.DeferredPromise();
					var lua = 'redis.call("LPUSH", "$REDIS_IP_ADDRESS_POOL", "' + remainingIpAddress.join('", "') + '")';
					var command :Array<Dynamic> = [lua, 0];
					redis.eval(command, function(err, out) {
						if (err != null) {
							Log.error(err);
							promise.boundPromise.reject(err);
							return;
						}
						promise.resolve(out);
					});
					return promise.boundPromise.thenTrue();
				} else {
					return Promise.promise(true);
				}
			})
			.thenTrue();
	}

	public static function getVagrantBoxes(rootPath :String) :Array<VagrantPath>
	{
		return FsExtended.listDirsSync(rootPath).filter(function(s) return s.startsWith(MACHINE_PREFIX))
			.map(function(p) return new VagrantPath(Path.join(rootPath, p))).array();
	}

	public static function getVagrantBoxPath(rootPath :String, id :MachineId) :VagrantPath
	{
		return getVagrantBoxes(rootPath).find(function(path :String) return path.indexOf(id) > -1);
	}

	public static function getAllVagrantBoxStatus(rootPath :String) :Promise<Array<VagrantStatus>>
	{
		var vagrantPaths = getVagrantBoxes(rootPath);

		return Promise.whenAll(vagrantPaths.map(function(path) {
			return getVagrantStatus(path);
		}))
		.then(function(statuses) {
			//Put the running machines in the front
			statuses.sort(function(s1, s2) {
				if (s1.status == VagrantMachineStatus.Running && s1.status != VagrantMachineStatus.Running) {
					return -1;
				} else if (s1.status != VagrantMachineStatus.Running && s1.status == VagrantMachineStatus.Running) {
					return 1;
				} else {
					return 0;
				}
			});
			return statuses;
		});
	}

	public static function getVagrantStatus(path :VagrantPath) :Promise<VagrantStatus>
	{
		return VagrantTools.getMachineStatus(path)
			.then(function(status :js.npm.Vagrant.StatusResult) {
				return {id:path.getMachineId(), path:path, status:status.status};
			});
	}

	// static function createWorkerBox(path :VagrantPath, ?streams :StdStreams) :Promise<Bool>
	// {
	// 	Log.info('createWorkerBox path=${path}');
	// 	return VagrantTools.ensureVagrantBoxRunning(path, streams)
	// 		.pipe(function(vagrantMachine) {
	// 			return getSshConnection(path);
	// 		})
	// 		.pipe(function(sshClient) {
	// 			return WorkerTools.setupCoreOS(sshClient, streams);
	// 		})
	// 		.thenTrue();
	// }

	public static function getSshConnection(path :VagrantPath) :Promise<SshClient>
	{
		return getSshConfig(path)
			.pipe(function(sshConfig :ConnectOptions) {
				return SshTools.getSsh(sshConfig);
			});
	}

	public static function getNextIpAddress(redis :RedisClient) :Promise<IP>
	{
		var promise = new promhx.deferred.DeferredPromise();
		redis.lpop(REDIS_IP_ADDRESS_POOL, function(err, multi) {
			if (err != null) {
				promise.boundPromise.reject(err);
				return;
			}
			promise.resolve(new IP(Std.string(multi)));
		});
		return promise.boundPromise;
	}

	public static function returnIpAddress(redis :RedisClient, ip :IP) :Promise<Int>
	{
		var promise = new promhx.CallbackPromise();
		redis.lpush(REDIS_IP_ADDRESS_POOL, ip, promise.cb2);
		return promise;
	}

	static function getIpFromPath(path :String) :String
	{
		var tokens = path.split('__');
		return tokens[tokens.length - 1].replace('_', '.');
	}

	// public static function XXXsetWorkerCountStatic(redis :RedisClient, rootPath :String, target :Int) :Promise<Bool>
	// {
	// 	//First set the target, so updates can be (sorta) idempotent
	// 	return RedisPromises.setHashInt(redis, REDIS_DATA, REDIS_TARGET, target)
	// 		.pipe(function(_) {
	// 			return updateStatus(redis, rootPath);
	// 		});
	// }

	/**
	 * This is meant to be (sorta) idempotent
	 * @param  redis    :RedisClient  [description]
	 * @param  rootPath :String       [description]
	 * @return          [description]
	 */
	// static function XXXupdateStatus(redis :RedisClient, rootPath :String, ?streams :StdStreams) :Promise<Bool>
	// {
	// 	var targetMachineCount;
	// 	//First get relevant info
	// 	return RedisPromises.getHashInt(redis, REDIS_DATA, REDIS_TARGET)
	// 		.pipe(function(target) {
	// 			targetMachineCount = target;
	// 			return InstancePool.getInstancesInPool(redis, ID);
	// 		})
	// 		.pipe(function(statuses :Array<{id:MachineId,status:MachineStatus}>) {
	// 			//Then take action
	// 			var promises = new Array<Promise<Dynamic>>();
	// 			var readyMachines = statuses.filter(InstancePool.isMachineHeadingTowardsReadiness);
	// 			//Add new machines?
	// 			if (targetMachineCount > readyMachines.length) {
	// 				var numNewMachines = targetMachineCount - readyMachines.length;
	// 				//First just change idle machines instead of spinning up new ones
	// 				var deferredMachines = statuses.filter(InstancePool.isStatus(MachineStatus.WaitingForRemoval));
	// 				while(numNewMachines > 0 && deferredMachines.length > 0) {
	// 					var machineId = deferredMachines.pop().id;
	// 					//Is it really idle? What if it had jobs but was waiting to be shut down?
	// 					promises.push(InstancePool.setInstanceStatus(redis, machineId, MachineStatus.Idle));
	// 					numNewMachines--;
	// 				}
	// 				while (numNewMachines > 0) {
	// 					promises.push(addMachine(redis, rootPath, streams));
	// 					numNewMachines--;
	// 				}
	// 			} else if (targetMachineCount < readyMachines.length) {
	// 				//Remove machines
	// 				//First mark as ready_for_removal any idle machines
	// 				var removeCount = readyMachines.length - targetMachineCount;
	// 				var idle = statuses.filter(InstancePool.isStatus(MachineStatus.Idle));
	// 				while(removeCount > 0 && idle.length > 0) {
	// 					var machineId = idle.pop().id;
	// 					promises.push(InstancePool.setInstanceStatus(redis, machineId, MachineStatus.WaitingForRemoval));
	// 					removeCount--;
	// 				}
	// 				//Then any working machines
	// 				var working = statuses.filter(InstancePool.isStatus(MachineStatus.Working));
	// 				while(removeCount > 0 && working.length > 0) {
	// 					var machineId = working.pop().id;
	// 					promises.push(InstancePool.setInstanceStatus(redis, machineId, MachineStatus.WaitingForRemoval));
	// 					removeCount--;
	// 				}
	// 				//Then finally max capacity machines
	// 				var maxCapacity = statuses.filter(InstancePool.isStatus(MachineStatus.MaxCapacity));
	// 				while(removeCount > 0 && maxCapacity.length > 0) {
	// 					var machineId = maxCapacity.pop().id;
	// 					promises.push(InstancePool.setInstanceStatus(redis, machineId, MachineStatus.WaitingForRemoval));
	// 					removeCount--;
	// 				}
	// 				//There should be no more machines to remove
	// 				if (removeCount > 0) {
	// 					Log.error('removeCount=$removeCount');
	// 				}

	// 				//Get any machines waiting for removal with no jobs, and completely remove them.
	// 			} else {
	// 				//Machine matches, do nothing
	// 			}
	// 			return Promise.whenAll(promises);
	// 		})
	// 		.pipe(function(_) {
	// 			return ComputeQueue.processPending(redis);
	// 		})
	// 		.pipe(function(_) {
	// 			return cleanup(redis, rootPath, streams);
	// 		})
	// 		.thenVal(true);
	// }
}

abstract VagrantPath(String) to String from String
{
	inline public function new (s: String)
		this = s;

	inline public function getMachineId() :MachineId
	{
		var tokens = this.split('__');
		return new MachineId(tokens[tokens.length - 2]);
	}

	inline public function getIp() :IP
	{
		var tokens = this.split('__');
		return new IP(tokens[tokens.length - 1].split('_').join('.'));
	}

	inline public function removeBasePath() :String
	{
		return WorkerProviderVagrantTools.MACHINE_PREFIX + getMachineId() + '__' + getIp().replace('.', '_');
	}

	inline public function getLastIpDigit() :Int
	{
		return getIp().getDigits()[3];
	}

	inline public static function from(id :MachineId, ip :IP) :VagrantPath
	{
		return new VagrantPath(WorkerProviderVagrantTools.MACHINE_PREFIX + id + '__' + ip.replace('.','_'));
	}
}
