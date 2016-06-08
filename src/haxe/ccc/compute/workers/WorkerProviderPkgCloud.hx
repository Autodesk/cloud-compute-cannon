package ccc.compute.workers;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;

import js.npm.Docker;
import js.npm.PkgCloud;
import js.npm.RedisClient;
import js.npm.Ssh;

import ccc.compute.InstancePool;
import ccc.compute.Definitions;
import ccc.compute.Definitions.Constants.*;
import ccc.compute.execution.Job;

import promhx.Promise;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.CallbackPromise;
import promhx.RedisPromises;
import promhx.RetryPromise;
import promhx.RequestPromises;

import util.SshTools;

import t9.abstracts.time.*;
import t9.abstracts.net.*;

using promhx.PromiseTools;
using Lambda;
using StringTools;

typedef ServiceConfigurationWorkerProviderPkgCloud = {>ServiceConfigurationWorkerProvider,
	var credentials :ClientOptionsAmazon;
	var worker :WorkerOptionsAmazon;
	var server :WorkerOptionsAmazon;
}

typedef WorkerOptionsAmazon = {>ServiceConfigurationWorkerProvider,
	@:optional var name :String;
	@:optional var Tags :Array<Dynamic<String>>;
	var InstanceType :String;
	var ImageId :String;
	var KeyName :String;
	var Key :String;
	@:optional var SecurityGroupId :String;
	@:optional var SubnetId :String;
	@:optional var usePublicIp :Bool;
}

class WorkerProviderPkgCloud extends WorkerProviderBase
{
	public static function getPublicHostName(config :ServiceConfigurationWorkerProviderPkgCloud) :Promise<HostName>
	{
		return switch(config.credentials.provider) {
			case amazon:
				return getAWSPublicHostName();
			case google:
				throw 'Not yet implemented: google ip handling';
		}
	}

	public static function getPrivateHostName(config :ServiceConfigurationWorkerProviderPkgCloud) :Promise<HostName>
	{
		return switch(config.credentials.provider) {
			case amazon:
				return getAWSPrivateHostName();
			case google:
				throw 'Not yet implemented: google ip handling';
		}
	}

	public var compute (get, null) :ComputeClientP;

	var _compute :ComputeClientP;
	var _serversCache :Map<String,PkgCloudServer> = new Map();

	static var PROVIDERS = new Map<String, WorkerProviderBase>();

	public function new (?config :ServiceConfigurationWorkerProvider)
	{
		super(config);
		initClient();
	}

	@post
	override public function postInjection()
	{
		Assert.notNull(_config);
		initClient();
		//Assume that servers with the same image id are our workers.
		//Ideally we would just tag the images, or use names, but that
		//isn't working in PkgCloud as of yet.
		_ready = super.postInjection()
			.pipe(function(_) {
				return getPrivateHostName(cast _config)
					.then(function(hostname) {
						Constants.SERVER_HOSTNAME_PRIVATE = hostname;
						Constants.REGISTRY = new Host(new HostName(Constants.SERVER_HOSTNAME_PRIVATE), new Port(REGISTRY_DEFAULT_PORT));
						Log.debug('SERVER_HOSTNAME_PRIVATE=${Constants.SERVER_HOSTNAME_PRIVATE}');
						return true;
					});
			})
			.pipe(function(_) {
				return getPublicHostName(cast _config)
					.then(function(hostname) {
						Constants.SERVER_HOSTNAME_PUBLIC = hostname;
						Log.debug('SERVER_HOSTNAME_PUBLIC=${Constants.SERVER_HOSTNAME_PUBLIC}');
						return true;
					});
			})
			.then(function(_) {
				log.info('Finished initializing provider=$id');
				return true;
			});

		addRunningPromiseToQueue(_ready);
		return _ready;
	}

	override public function createWorker() :Promise<WorkerDefinition>
	{
		var promise = super.createWorker();
		if (promise != null) {
			log.info('createWorker using a deferred worker');
			return promise;
		} else {
			log.info('createWorker create a whole new instance');
			return __createWorkerNext();
		}
	}

	override public function destroyInstance(instanceId :MachineId) :Promise<Bool>
	{
		return super.destroyInstance(instanceId)
			.pipe(function(_) {
				if (_compute != null) {
					return compute.destroyServer(instanceId)
						.then(function(_) {
							log.info({log:'instance_destroyed', instance:instanceId, f:'destroyIntance'});
							return _;
						})
						.thenTrue()
						.errorPipe(function(err) {
							log.warn({error:err, f:'destroyIntance', instance:instanceId});
							return Promise.promise(false);
						});
				} else {
					return Promise.promise(false);
				}
			});
	}

	function initClient()
	{
		if (getConfig() != null && _compute == null) {
			this.id = getConfig().credentials.provider + '';
			log.info({log:'Initializing provider=$id', provider:id});
			Assert.that(!PROVIDERS.exists(this.id));
			PROVIDERS.set(this.id, this);
			_compute = cast PkgCloud.compute.createClient(getConfig().credentials);
			var type :ProviderType = cast id;
		}
	}

	function __createWorkerNext() :Promise<WorkerDefinition>
	{
		log.info('provider=$id createWorker');
		var promise = _ready
			.pipe(function(_) {
				var workerDef :WorkerDefinition;
				var promise = Promise.promise(true)
					.pipe(function(_) {
						return createIndependentWorker();
					})
					.pipe(function(result) {
						workerDef = result;
						//Remove the ssh key when logging
						var logDef = Reflect.copy(workerDef);
						logDef.ssh = Reflect.copy(workerDef.ssh);
						Reflect.deleteField(logDef.ssh, 'privateKey');
						Log.info('provider=$id new worker ${workerDef.id} testing ssh connectivity workerDef=$logDef');
						//Test ssh and docker connectivity
						return SshTools.getSsh(workerDef.ssh, 60, 2000, PollType.regular)
							.pipe(function(ssh) {
								log.info('provider=$id new worker ${workerDef.id} get machine parameters via docker API');
								return WorkerProviderTools.getWorkerParameters(workerDef.docker);
							})
							.pipe(function(parameters) {
								log.info('provider=$id new worker ${workerDef.id} adding worker to pool!');
								return InstancePool.addInstance(_redis, id, workerDef, parameters);
							})
							.then(function(_) {
								return workerDef;
							})
							.errorPipe(function(err) {
								log.error('Failed to connect to worker=${workerDef.id}, destroying server and retrying err=$err');
								return InstancePool.removeInstance(_redis, workerDef.id)
									.pipe(function(_) {
										log.info('_compute.destroyServer');
										return _compute.destroyServer(workerDef.id);
									})
									.then(function(_) {
										log.info('Destroyed ${workerDef.id}');
										return workerDef;
									});
							});
					});
				return promise;
			});
		addRunningPromiseToQueue(promise);
		return promise;
	}

	override public function dispose()
	{
		PROVIDERS.remove(this.id);
		_compute = null;
		return super.dispose();
	}

	/**
	 * Get the optimal time to actually shut down the instance
	 * depending on the cloud provider
	 * @param  workerId :MachineId    [description]
	 * @return          [description]
	 */
	override function getShutdownDelay(workerId :MachineId) :Promise<Minutes>
	{
		var type :ProviderType = cast id;
		switch(type) {
			case amazon:
				/**
				 * Amazon instance are billed per hour
				 * https://aws.amazon.com/ec2/pricing/
				 * So we get the remainder of the hour for this instance
				 * and shutdown just before the hour elapses.
				 */
				log.info({f:'getShutdownDelay', workerId:workerId, log:'getServer'});
				return getServer(workerId)
					.then(function(worker) {
						/*
						 *	We could get this from configuration, but since this
						 *	value is unlikely to change in the near future, lets
						 *	hard code it to avoid billing mistakes.
						 */
						var billingIncrement = _config.billingIncrement;
						var awsServer :PkgCloudServerAws = cast worker;
						var launchTime = awsServer.launchTime;
						var launchTimeSince1970Ms :Milliseconds = untyped __js__('new Date({0}).getTime()', launchTime);
						var launchTimeSince1970 = new TimeStamp(launchTimeSince1970Ms);
						var now = TimeStamp.now();
						var minutesSinceLaunch = (now - launchTimeSince1970).toMinutes();
						var remainingMinutesTheIncrement = minutesSinceLaunch % billingIncrement;
						var delay = billingIncrement - remainingMinutesTheIncrement;
						delay = delay - new Minutes(1);
						if (delay < new Minutes(0)) {
							delay = new Minutes(0);
						}
						return delay;
					});
			case google:
				return super.getShutdownDelay(workerId);
			default:
				return super.getShutdownDelay(workerId);
		};
	}

	/** Completely remove the instance */
	override function shutdownWorker(workerId :MachineId) :Promise<Bool>
	{
		log.info('provider=$id worker=$workerId destroying destroying instance');
		return destroyInstance(workerId);
		
		// if (_compute != null) {
		// 	return _compute.destroyServer(workerId)
		// 		.thenTrue()
		// 		.errorPipe(function(err) {
		// 			Log.error('shutdownWorker err (This might be fine)=$err');
		// 			return Promise.promise(true);
		// 		});
		// } else {
		// 	return Promise.promise(true);
		// }
	}

	override public function shutdownAllWorkers() :Promise<Bool>
	{
		return InstancePool.getInstancesInPool(_redis, id)
			.pipe(function(workerStatuses) {
				return Promise.whenAll(workerStatuses.map(function(w) {
					return shutdownWorker(w.id);
				}));
			})
			.thenTrue();
	}

	override public function createIndependentWorker() :Promise<WorkerDefinition>
	{
		return _ready
			.pipe(function(_) {
				var config = getConfig();
				return createInstance(config.credentials, config.worker, true);
			});
	}

	override public function createServer() :Promise<WorkerDefinition>
	{
		return _ready
			.pipe(function(_) {
				var config = getConfig();
				return createInstance(config.credentials, config.server, false);
			});
	}

	function getServer(workerId :MachineId, useCache :Bool = true) :Promise<PkgCloudServer>
	{
		if (useCache && _serversCache != null && _serversCache.exists(workerId)) {
			return Promise.promise(_serversCache.get(workerId));
		} else {
			Assert.notNull(_compute, '_compute==null');
			log.info({f:'getServer', instance_id:workerId, log:'getServer'});
			return _compute.getServer(workerId)
				.then(function(server) {
					if (server != null && _serversCache != null) {
						_serversCache.set(workerId, server);
					}
					return server;
				});
		}
	}

	override public function getNetworkHost() :Promise<Host>
	{
		return getAWSPrivateNetworkIp()
			.then(function(hostname) {
				return new Host(hostname, new Port(SERVER_DEFAULT_PORT));
			});
	}

	static function getAWSPrivateNetworkIp() :Promise<IP>
	{
		return RequestPromises.get('http://169.254.169.254/latest/meta-data/local-ipv4')
			.then(function(s) {
				return new IP(s.trim());
			});
	}

	static function getAWSPublicNetworkIp() :Promise<IP>
	{
		return RequestPromises.get('http://169.254.169.254/latest/meta-data/public-ipv4')
			.then(function(s) {
				return new IP(s.trim());
			});
	}

	static function getAWSPrivateHostName() :Promise<HostName>
	{
		return RequestPromises.get('http://169.254.169.254/latest/meta-data/local-hostname')
			.then(function(s) {
				return new HostName(s.trim());
			});
	}

	static function getAWSPublicHostName() :Promise<HostName>
	{
		return RequestPromises.get('http://169.254.169.254/latest/meta-data/public-hostname')
			.then(function(s) {
				return new HostName(s.trim());
			});
	}

	inline function get_compute() :ComputeClientP
	{
		return _compute;
	}

	/** Just does a cast */
	inline function getConfig() :ServiceConfigurationWorkerProviderPkgCloud
	{
		return cast _config;
	}

	/**
	 * When we need to log the config but don't want to put the
	 * private key in the logs
	 */
	static function getLogSafeConfig(config :Dynamic)
	{
		var copy :ServiceConfigurationWorkerProviderPkgCloud = Reflect.copy(config);
		copy.worker = Reflect.copy(copy.worker);
		Reflect.deleteField(copy.worker, 'Key');
		return copy;
	}

	static function getIpFromServer(server :PkgCloudServer, ?usePublic :Bool = false) :String
	{
		var addresses :Array<String> = Reflect.field(server.addresses, 'public');
		if (usePublic && addresses != null && addresses.length > 0) {
			return addresses[0];
		} else {
			addresses = Reflect.field(server.addresses, 'private');
			return addresses[0];
		}
	}

	public static function createInstance(credentials :ClientOptionsAmazon, instanceParameters :WorkerOptionsAmazon, isWorker :Bool, ?log :AbstractLogger) :Promise<WorkerDefinition>
	{
		return createPkgCloudInstance(credentials, instanceParameters, isWorker, log)
			.then(function(server) {
				var usePublicIp = !isWorker || instanceParameters.usePublicIp;
				var host = getIpFromServer(server, usePublicIp);
				var hostPublic = getIpFromServer(server, true);
				var hostPrivate = getIpFromServer(server, false);
				var workerDef :WorkerDefinition = {
					id: server.id,
					hostPublic: new HostName(hostPublic),
					hostPrivate: new HostName(hostPrivate),
					ssh: {
						host: host,
						port: 22,
						username: 'core',
						privateKey: instanceParameters.Key
					},
					docker: {
						host: host,
						port: 2375,
						protocol: 'http'
					}
				};
				return workerDef;
			});
	}

	public static function createPkgCloudInstance(credentials :ClientOptionsAmazon, instanceParameters :WorkerOptionsAmazon, isWorker :Bool, ?log :AbstractLogger) :Promise<PkgCloudServer>
	{
		log = Logger.ensureLog(log, {f:'createPkgCloudInstance', isWorker:isWorker});
		var optionsAmazon :WorkerOptionsAmazon = Reflect.copy(instanceParameters);
		var optionsAmazonForLogging :WorkerOptionsAmazon = Reflect.copy(instanceParameters);
		Reflect.deleteField(optionsAmazonForLogging, 'Key');
		log.debug({optionsAmazon:optionsAmazonForLogging});
		var isPublicIp = optionsAmazon.usePublicIp || !isWorker;
		var instanceType = isWorker ? 'worker' : 'server';
		var client :ComputeClientP = cast PkgCloud.compute.createClient(credentials);
		Assert.notNull(client, 'createPkgCloudInstance client==null');
		var type :ProviderType = credentials.provider;
		log = log.child({'type':type});
		log.debug('creating new $instanceType');
		return Promise.promise(true)
			.pipe(function(_) {
				switch(type) {
					case amazon:
						log.debug('creating aws instance');
						/*
						 * Using the amazon pkgcloud API directly is not sufficient for our purposes,
						 * since some options are not exposed, e.g. specifying the SubnetId.
						 * So instead, we grab the EC2 object from the client object, and interact
						 * directly with the AWS-SDK.
						 */
						Reflect.deleteField(optionsAmazon, 'Key');
						//Do some raw stuff via the direct AWS object
						//http://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/EC2.html#runInstances-property
						var ec2 :{runInstances:Dynamic->(Dynamic->Dynamic->Void)->Void, createTags:Dynamic->(Dynamic->Void)->Void} = Reflect.field(client, 'ec2');
						// log.trace('client=${client}');
						Assert.notNull(ec2, 'Missing ec2 field from pkgcloud client');
						var meta = {name: optionsAmazon.name};
						var options = {
							UserData: null,
							MinCount: 1,
							MaxCount: 1,
							ImageId: optionsAmazon.ImageId,
							InstanceType: optionsAmazon.InstanceType,
							KeyName: optionsAmazon.KeyName,
						};
						//http://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/EC2.html#runInstances-property
						if (isPublicIp && Reflect.hasField(optionsAmazon, 'SubnetId')) {
							Reflect.setField(options, 'NetworkInterfaces', [{'AssociatePublicIpAddress':true, SubnetId:optionsAmazon.SubnetId, DeviceIndex:0}]);
						} else if (Reflect.hasField(optionsAmazon, 'SubnetId')) {
							Reflect.setField(options, 'SubnetId', optionsAmazon.SubnetId);
						}

						if (optionsAmazon.SecurityGroupId != null) {
							Reflect.setField(options, 'SecurityGroupIds', [optionsAmazon.SecurityGroupId]);
						}
						log.debug({message:'AWS $instanceType', options:options});
						var promise = new DeferredPromise();
						ec2.runInstances(options, function(err, data :{Instances:Array<Dynamic>}) {
							log.trace('in runInstances!!!!');
							if (err != null) {
								log.error({log:'runInstances', error:err});
								promise.boundPromise.reject(err);
								return;
							}
							// log.trace({message:'runInstances', data:data});
							var instanceId = data.Instances[0].InstanceId;
							var tags = optionsAmazon.Tags == null ? [] : optionsAmazon.Tags;

							function getServerAndResolve() {
								client.getServer(instanceId)
									.then(function(server) {
										promise.resolve(server);
									});
							}
							// Add tags to the instance
							if (tags.length == 0) {
								getServerAndResolve();
							} else {
								var tagParams = {Resources: [instanceId], Tags: tags};
								ec2.createTags(tagParams, function(err) {
									log.trace('Tagging $instanceType $instanceId with $tags '+ (err != null? "failure" : "success"));
									if (err != null) {
										log.error({log:'createTags', error:err});
									}
									log.debug({log:'done tagging, client.getServer'});
									getServerAndResolve();
								});
							}
						});
						return promise.boundPromise;
					default:
						log.error({log:'Untested PkgCloud provider'});
						return client.createServer(Reflect.copy(instanceParameters));
				}
			})
			.pipe(function(server) {
				var promise = new DeferredPromise();
				//Poll every interval until the status is running
				var f = null;
				var status = null;
				f = function() {
					log.info({f:'createPkgCloudInstance', instance_id:server.id, message:'getServer'});
					client.getServer(server.id)
						.then(function(server) {
							if (server.status != status) {
								log.debug({log:'provider=$type creating new $instanceType ${server.id} ${server.status}'});
								status = server.status;
							}
							log.trace({server_status:server.status, addresses:server.addresses});
							var optionsAmazon :WorkerOptionsAmazon = Reflect.copy(instanceParameters);
							var host = getIpFromServer(server, isPublicIp);
							if (server.status == PkgCloudComputeStatus.running && host != null && host != '') {
								promise.resolve(server);
							} else {
								haxe.Timer.delay(f, 4000);//4 seconds
							}
						});
				}
				f();
				return promise.boundPromise;
			})
			.pipe(function(server) {
				var optionsAmazon :WorkerOptionsAmazon = instanceParameters;
				var host = getIpFromServer(server, isPublicIp);
				if (host == null) {
					throw 'Could not find public IP in server=$server';
				}
				var sshOptions :ConnectOptions = {
					host: host,
					port: 22,
					username: 'core',
					privateKey: optionsAmazon.Key
				}

				Log.info('provider=$type new $instanceType ${server.id} set up instance');
				return WorkerProviderTools.pollInstanceUntilSshReady(sshOptions)
					.pipe(function(_) {
						log.info('SSH connection to instance established!');
						log.info('provider=$type new $instanceType ${server.id} set up instance');
						//Update CoreOs to allow docker access
						//AWS specific
						return WorkerProviderTools.setupCoreOS(sshOptions)
							.then(function(_) {
								return server;
							});
					});
			});
	}
}

//https://coreos.com/dist/aws/aws-stable.json
typedef CoreOSAwsJson = Dynamic<{hvm:String,pv:String}>;
