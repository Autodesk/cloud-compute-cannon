package ccc.compute.server.scaling.aws;

import haxe.Resource;

import js.npm.PkgCloud;

using t9.util.ColorTraces;

typedef InstanceOptionsAmazon = {
	var InstanceType :String;
	var ImageId :String;
	var KeyName :String;
	var Key :String;
	@:optional var SecurityGroupId :String;
	@:optional var SubnetId :String;
	@:optional var MinCount :Int;
	@:optional var MaxCount :Int;
}

@:enum
abstract AmazonEc2State(String) {
	var Created = 'created';
	var Tagged = 'tagged';
}

class CloudProviderAws
	implements ICloudProvider
{
	@inject public var _injector :Injector;
	@inject public var log :AbstractLogger;
	@inject public var _docker :Docker;
	var _instanceId :MachineId;
	var _hostPublic :String;
	var _hostPrivate :String;

	public var compute (get, null) :ComputeClientP;
	var _compute :ComputeClientP;
	inline function get_compute() :ComputeClientP {return _compute;}

	public var config (get, null) :ServiceConfigurationWorkerProvider;
	@inject public var _config :ServiceConfigurationWorkerProvider;
	inline function get_config() :ServiceConfigurationWorkerProvider {return _config;}

	public function new() {}

	@post public function postInject()
	{
		log = log.child({c:Type.getClassName(Type.getClass(this)).split('.').pop()});
		// ServerConfigTools.getProviderConfig(_injector)
		// 	.then(function(c) {
		// 		_config = c;
				_compute = cast PkgCloud.compute.createClient(_config.credentials);
			// });
	}

	public function getId() :Promise<MachineId>
	{
		if (_instanceId != null) {
			return Promise.promise(_instanceId);
		} else {
			return RequestPromises.get('http://169.254.169.254/latest/meta-data/instance-id')
				.then(function(instanceId) {
					_instanceId = instanceId.trim();
					log = log.child({instanceId:_instanceId});
					return _instanceId;
				})
				.errorPipe(function(err) {
					log.error({error:err});
					return Promise.promise(null);
				});
		}
	}

	public function getHostPublic() :Promise<String>
	{
		if (_hostPublic != null) {
			return Promise.promise(_hostPublic);
		} else {
			return getAWSPublicNetworkIp()
				.then(function(ip) {
					_hostPublic = ip;
					return _hostPublic;
				});
		}
	}

	public function getHostPrivate() :Promise<String>
	{
		if (_hostPrivate != null) {
			return Promise.promise(_hostPrivate);
		} else {
			return getAWSPrivateNetworkIp()
				.then(function(ip) {
					_hostPrivate = ip;
					return _hostPrivate;
				});
		}
	}

	/**
	 * For local docker, containers can shut down immediately.
	 * @return [description]
	 */
	public function getBestShutdownTime() :Promise<Float>
	{
		return Promise.promise(Date.now().getTime() - 1000);
	}

	public function shutdownThisInstance() :Promise<Bool>
	{
		return Promise.promise(true);
	}

	public function createWorker() :Promise<Bool>
	{
		var promise = new DeferredPromise();

		return promise.boundPromise;
	}

	public function terminate(id :MachineId) :Promise<Bool>
	{
		return Promise.promise(true);
	}

	public function dispose() :Promise<Bool>
	{
		return Promise.promise(true);
	}

	public function getDiskUsage() :Promise<Float>
	{
		return awsDockerDiskUsage(_docker);
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

	function __createWorkerNext() :Promise<WorkerDefinition>
	{
		log.info(' createWorker');
		var workerDef :WorkerDefinition;
		return Promise.promise(true)
			.pipe(function(_) {
				return createInstance(get_config(), MachineType.worker);
			})
			.pipe(function(result) {
				workerDef = result;
				//Remove the ssh key when logging
				var logDef = Reflect.copy(workerDef);
				logDef.ssh = Reflect.copy(workerDef.ssh);
				Reflect.deleteField(logDef.ssh, 'privateKey');
				Log.info('new worker ${workerDef.id} testing ssh connectivity workerDef=$logDef');
				//Test ssh and docker connectivity
				return SshTools.getSsh(workerDef.ssh, 60, 2000, PollType.regular)
					// .pipe(function(ssh) {
					// 	log.info('new worker ${workerDef.id} get machine parameters via docker API');
					// 	return WorkerProviderTools.getWorkerParameters(workerDef.docker);
					// })
					// .pipe(function(parameters) {
					// 	log.info('provider=$id new worker ${workerDef.id} adding worker to pool!');
					// 	return InstancePool.addInstance(_redis, id, workerDef, parameters);
					// })
					.then(function(_) {
						return workerDef;
					})
					.errorPipe(function(err) {
						log.error('Failed to connect to worker=${workerDef.id}, destroying server and retrying err=$err');
						// return InstancePool.removeInstance(_redis, workerDef.id)
						return Promise.promise(true)
							.pipe(function(_) {
								log.info('destroy_instance');
								return _compute.destroyServer(workerDef.id);
							})
							.then(function(_) {
								log.info('Destroyed ${workerDef.id}');
								return workerDef;
							});
					});
			});
	}

	static function awsDockerDiskUsage(docker :Docker) :Promise<Float>
	{
		var volumes :Array<MountedDockerVolumeDef> = [
			{
				mount: '/var/lib/docker',
				name: '/var/lib/docker'
			}
		];
		return DockerTools.runDockerCommand(docker, DOCKER_IMAGE_DEFAULT, ["df", "-h", "/var/lib/docker/"], null, volumes)
			.then(function(runResult) {
				var diskUse = ~/.*Mounted on\r\n.+\s+.+\s+.+\s+([0-9]+)%.*/igm;
				if (runResult.StatusCode == 0 && diskUse.match(runResult.stdout)) {
					var diskUsage = Std.parseFloat(diskUse.matched(1)) / 100.0;
					Log.debug({disk:diskUsage});
					return diskUsage;
				} else {
					Log.warn('awsDockerDiskHealthCheck: Non-zero exit code or did not match regex: ${runResult}');
					return 1.0;
				}
			});
	}

	public static function createInstance(config :ServiceConfigurationWorkerProvider, machineType :String, ?redis :RedisClient, ?log :AbstractLogger) :Promise<WorkerDefinition>
	{
		return createPkgCloudInstance(config, machineType, redis, log)
			.then(function(serverBlob) {
				var server = serverBlob.server;
				var ssh = serverBlob.ssh;
				var privateIp = serverBlob.privateIp;
				var workerDef :WorkerDefinition = {
					id: server.id,
					hostPublic: new HostName(ssh.host),
					hostPrivate: new HostName(privateIp),
					ssh: ssh,
					docker: {
						host: privateIp,
						port: 2375,
						protocol: 'http'
					}
				};
				traceGreen('    - created remote server ${server.id} at ${ssh.host}');
				return workerDef;
			});
	}

	public static function createPkgCloudInstance(config :ServiceConfigurationWorkerProvider, machineType :String, ?redis :RedisClient, ?log :AbstractLogger) :Promise<{server:PkgCloudServer,ssh:ConnectOptions, privateIp: String}>
	{
		log = Logger.ensureLog(log, {f:'createPkgCloudInstance'});

		var credentials :ClientOptionsAmazon = cast config.credentials;
		var provider :CloudProvider = config;
		// var provider = config;
		//This call merges the default options and tags into the instance options and tags.
		var instanceDefinition :ProviderInstanceDefinition = provider.getMachineDefinition(machineType);// config.machines[machineType];
		if (instanceDefinition == null) {
			return PromiseTools.error('createPkgCloudInstance missing machine configuration for $machineType');
		}
		var isPublicIp = instanceDefinition.public_ip;//instanceDefinition.public_ip == null ? false : instanceDefinition.public_ip;
		var client :ComputeClientP = cast PkgCloud.compute.createClient(credentials);
		var type :ProviderType = credentials.provider;
		log = log.child({'type':type});
		log.debug('creating new $machineType');
		return Promise.promise(true)
			.pipe(function(_) {
				switch(config.type) {
					case amazon:
						return getAWSInstanceId()
							.pipe(function(serverInstanceId) {

								var instanceOpts :InstanceOptionsAmazon = cast instanceDefinition.options;
								log.debug('creating aws instance');
								/*
								 * Using the amazon pkgcloud API directly is not sufficient for our purposes,
								 * since some options are not exposed, e.g. specifying the SubnetId.
								 * So instead, we grab the EC2 object from the client object, and interact
								 * directly with the AWS-SDK.
								 */
								//Do some raw stuff via the direct AWS object
								//http://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/EC2.html#runInstances-property
								var ec2 :{runInstances:Dynamic->(Dynamic->Dynamic->Void)->Void, createTags:Dynamic->(Dynamic->Void)->Void} = Reflect.field(client, 'ec2');
								Assert.notNull(ec2, 'Missing ec2 field from pkgcloud client');
								instanceOpts.MinCount = 1;
								instanceOpts.MaxCount = 1;
								log.debug({message:'AWS $machineType', options:LogTools.removePrivateKeys(instanceOpts)});
								log.info("create_instance");
								var promise = new DeferredPromise();
								js.Node.process.stdout.write('    - creating instance\n'.yellow());
								ec2.runInstances(instanceOpts, function(err, data :{Instances:Array<Dynamic>}) {
									if (err != null) {
										log.error({log:'runInstances', error:err});
										promise.boundPromise.reject(err);
										return;
									}
									// log.trace({message:'runInstances', data:data});
									var instanceId = data.Instances[0].InstanceId;
									js.Node.process.stdout.write('        - $instanceId created\n'.green());

									var poolId = ServiceWorkerProviderType.pkgcloud;

									//Get tags, merge default and instance specific
									var tags = [];
									tags.push({Key:INSTANCE_TAG_TYPE_KEY, Value:machineType});
									tags.push({Key:INSTANCE_TAG_OWNER_KEY, Value:serverInstanceId});

									//Custom tags
									for (tagName in instanceDefinition.tags.keys()) {
										tags.push({Key:tagName, Value:instanceDefinition.tags[tagName]});
									}

									//Create an object for better logging (avoiding the Key:Value verbosity)
									var tagsForLogging :DynamicAccess<String> = {};
									for (tag in tags) {
										tagsForLogging[tag.Key] = tag.Value;
									}

									function getServerAndResolve() {
										client.getServer(instanceId)
											.then(function(server) {
												promise.resolve(server);
											});
									}
									// Add tags to the instance
									js.Node.process.stdout.write('    - tagging $instanceId with ${Json.stringify(tagsForLogging)}\n'.yellow());
									var tagParams = {Resources: [instanceId], Tags: tags};
									ec2.createTags(tagParams, function(err) {
										js.Node.process.stdout.write('        - successfully tagged\n'.green());
										log.trace('Tagging $machineType $instanceId with $tags '+ (err != null? "failure" : "success"));
										if (err != null) {
											js.Node.process.stdout.write('failed to tag instance, error=$err'.red());
											log.error({log:'createTags', error:err});
										}
										log.debug({log:'done tagging, client.getServer'});
										getServerAndResolve();
									});
								});
								return promise.boundPromise;
							});
				}
			})
			.pipe(function(server) {
				Node.process.stdout.write('    - polling ${server.id} via provider API'.yellow());
				var promise = new DeferredPromise();
				//Poll every interval until the status is running
				var f = null;
				var status = null;
				f = function() {
					log.info({f:'createPkgCloudInstance', instance_id:server.id, message:'getServer'});
					Node.process.stdout.write('.'.yellow());
					client.getServer(server.id)
						.then(function(server) {
							if (server.status != status) {
								log.debug({log:'provider=$type creating new $machineType ${server.id} ${server.status}'});
								status = server.status;
							}
							// log.trace({server_status:server.status, addresses:server.addresses});
							var host = getIpFromServer(server, isPublicIp);
							if (server.status == PkgCloudComputeStatus.running && host != null && host != '') {
								Node.process.stdout.write('OK\n'.green());
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
				var host = getIpFromServer(server, isPublicIp || machineType == MachineType.server);
				var privateIp = getIpFromServer(server, false);
				if (host == null) {
					throw 'Could not find public IP in server=$server';
				}

				Assert.notNull(provider.getMachineKey(machineType), 'Cannot find ssh key in $provider for machine type $machineType');
				var sshOptions :ConnectOptions = {
					host: host,
					port: 22,
					username: 'core',
					privateKey: provider.getMachineKey(machineType)
				}

				Log.info('provider=$type new $machineType ${server.id} set up instance host=$host');
				Node.process.stdout.write('    - polling ${server.id} at host=${sshOptions.host} username=${sshOptions.username} via SSH'.yellow());
				return pollInstanceUntilSshReady(sshOptions, function() Node.process.stdout.write('.'.yellow()))
					.pipe(function(_) {
						Node.process.stdout.write('OK\n'.green());
						log.info('SSH connection to instance established!');
						log.info('provider=$type new $machineType ${server.id} set up instance');
						//Update CoreOs to allow docker access
						//AWS specific
						Node.process.stdout.write('    - setting up CoreOS\n'.yellow());
						return setupCoreOS(sshOptions)
							.then(function(_) {
								Node.process.stdout.write('      - OK\n'.green());
								return {server:server, ssh:sshOptions, privateIp:privateIp};
							});
					});
			});
	}


	static function getAWSPrivateHostName() :Promise<HostName>
	{
		return RequestPromises.get('http://169.254.169.254/latest/meta-data/local-hostname')
			.then(function(s) {
				return new HostName(s.trim());
			});
	}

	static function getAWSInstanceId() :Promise<MachineId>
	{
		return RequestPromises.get('http://169.254.169.254/latest/meta-data/instance-id')
			.then(function(s) {
				return s.trim();
			});
	}

	static function getAWSPublicHostName() :Promise<HostName>
	{
		return RequestPromises.get('http://169.254.169.254/latest/meta-data/public-hostname')
			.then(function(s) {
				return s != null ? new HostName(s.trim()) : null;
			});
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

	public static function pollInstanceUntilSshReady(sshOptions :ConnectOptions, ?attemptCallback :Void->Void) :Promise<Bool>
	{
		var retryAttempts = 240;
		var intervalMs = 2000;
		return SshTools.getSsh(sshOptions, retryAttempts, intervalMs, promhx.RetryPromise.PollType.regular, 'pollInstanceUntilSshReady', false, attemptCallback)
			.then(function(ssh) {
				ssh.end();
				return true;
			});
	}

	/**
	 * https://coreos.com/os/docs/latest/customizing-docker.html
	 * @param  worker :MachineDefinition [description]
	 * @return        [description]
	 */
	public static function setupCoreOS(sshOptions :ConnectOptions, ?log :AbstractLogger)
	{
		log = Logger.ensureLog(log, {f:setupCoreOS, host:sshOptions.host});

		log.debug({state:'start'});
		var retryAttempts = 12;
		var doublingTimeInterval = 200;
		log.debug({state:'get_ssh'});
		return SshTools.getSsh(sshOptions, retryAttempts, doublingTimeInterval)
			.pipe(function(ssh) {
				ssh.end();
				log.debug({state:'get_sftp'});
				log.debug({state:'writing_file'});
				var dockerSocketFile = 'etc/vagrant/coreos/docker-tcp.socket';
				Assert.notNull(Resource.getString(dockerSocketFile), 'Missing resource $dockerSocketFile');
				return SshTools.writeFileString(sshOptions, '/tmp/docker-tcp.socket', Resource.getString(dockerSocketFile))
					.pipe(function(_) {
						log.debug({state:'executing_custom_commands'});
						return SshTools.executeCommands(sshOptions, [
							//https://github.com/coreos/coreos-vagrant/issues/235
							//Set up the insecure registry config
							'sudo cp /usr/lib/systemd/system/docker.service /etc/systemd/system/',
							'sudo sed -e "/^ExecStart/ s|$$| --insecure-registry=0.0.0.0/0 |" -i /etc/systemd/system/docker.service',
							//This sets up the remote API
							'sudo cp /tmp/docker-tcp.socket /etc/systemd/system/docker-tcp.socket',
							'sudo systemctl enable docker-tcp.socket',
							'sudo systemctl stop -q docker', //Shuttup with your noisy output.
							//Insecure registry load
							'sudo systemctl daemon-reload',
							//Start the socket and restart docker
							'sudo systemctl start docker-tcp.socket',
							'sudo systemctl start docker',
							'sudo systemctl stop update-engine', //If workers reboot, it can cause problems for jobs
							'sudo mkdir -p "$WORKER_JOB_DATA_DIRECTORY_HOST_MOUNT"',
							'sudo chmod 777 "$WORKER_JOB_DATA_DIRECTORY_HOST_MOUNT"'
						]);
					})
					.pipe(function(_) {
						//Validate by checking the last command
						return SshTools.execute(sshOptions, 'ls "$WORKER_JOB_DATA_DIRECTORY_HOST_MOUNT"', 3, 100)
							.then(function(execResult) {
								if (execResult.code != 0) {
									throw 'Failed to set up CoreOS worker';
								}
								return true;
							});
					})
					.thenTrue();
			});
	}

}