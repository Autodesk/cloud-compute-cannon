package ccc.compute.server;

import ccc.compute.client.ClientTools;
import ccc.compute.InitConfigTools;
import ccc.compute.workers.WorkerProviderBoot2Docker;
import ccc.compute.workers.WorkerProviderVagrantTools;
import ccc.compute.workers.WorkerProviderPkgCloud;
import ccc.compute.workers.WorkerProviderTools;
import ccc.storage.ServiceStorage;
import ccc.storage.ServiceStorageLocalFileSystem;

import haxe.Json;
import haxe.Resource;
import haxe.Template;

import js.Node;
import js.node.Os;
import js.node.Path;
import js.npm.fsextended.FsExtended;
import js.npm.docker.Docker;
import js.npm.ssh2.Ssh;

import promhx.Promise;
import promhx.RequestPromises;
import promhx.deferred.DeferredPromise;

import t9.abstracts.net.*;

import util.DockerTools;
import util.Predicates;
import util.SshTools;
import util.streams.StreamTools;

import yaml.Yaml;

using Lambda;
using StringTools;
using promhx.PromiseTools;

typedef ProviderConfig=ServiceConfigurationWorkerProvider;

/**
 * General provider tools that aren't specifically about managing workers.
 */
class ProviderTools
{
	// public static function loadLocalServerConnection() :Promise<ServerConnectionBlob>
	// {
	// 	return isServerConfigStoredLocally()
	// 		.then(function(isLocalConfig) {
	// 			if (isLocalConfig) {
	// 				var serverDef :ServerConnectionBlob = Json.parse(FsExtended.readFileSync(SERVER_CONNECTION_FILE, {}));
	// 				return serverDef;
	// 			} else {
	// 				return null;
	// 			}
	// 		});
	// }


// 	public static function serverCheck(host :Host) :Promise<Bool>
// 	{
// 		return RequestPromises.get('http://${host}${Constants.SERVER_PATH_CHECKS}')
// 			.then(function(out) {
// 				return out == Constants.SERVER_PATH_CHECKS_OK;
// 			})
// 			.errorPipe(function(err) {//Don't care about the specific error
// #if tests
// 				Log.error(err);
// #end
// 				return Promise.promise(false);
// 			});
// 	}


	/**
	 * Saves the server configuration in the cwd.
	 * @param  blob :ServerConnectionBlob [description]
	 * @return      [description]
	 */
	// public static function saveLocalServerConnection(blob :ServerConnectionBlob) :Promise<Bool>
	// {
	// 	var base = Path.dirname(SERVER_CONNECTION_FILE);
	// 	FsExtended.ensureDirSync(base);
	// 	FsExtended.writeFileSync(SERVER_CONNECTION_FILE, Json.stringify(blob, null, '\t'));
	// 	return Promise.promise(true);
	// }

	/**
	 * Instantiates a server instance.
	 * @param  config :ProviderConfig [description]
	 * @return        [description]
	 */
	// public static function buildRemoteServer(config :ProviderConfig) :Promise<InstanceDefinition>
	// {
	// 	trace('buildRemoteServer');
	// 	return createServerInstance(config)
	// 		.pipe(function(instanceDef :InstanceDefinition) {
	// 			//Write the server config
	// 			// trace('buildRemoteServer instanceDef=$instanceDef');
	// 			// var serverBlob :ServerConnectionBlob = {
	// 			// 	server: instanceDef,
	// 			// 	provider: config
	// 			// };
	// 			// CliTools.writeServerConnection(serverBlob, Node.process.cwd());
	// 			trace('buildRemoteServer installServer');
	// 			return installServer({server:instanceDef, provider:config})
	// 				.then(function(_) {
	// 					return instanceDef;
	// 				});
	// 		});
	// }

	/**
	 * Get the docker connection config to the CCC server.
	 * @param  config :ProviderConfig [description]
	 * @return        [description]
	 */
	// public static function getServerDocker(config :ProviderConfig) :Promise<Docker>
	// {
	// 	//Check for saved credentials on disk
	// 	//If creds exist, grab the host out of them
	// 	//Else boot up a server instance, and then
	// 	//get creds.
	// 	return ensureRemoteServer(config)
	// 		.then(function(serverConnectionBlob) {
	// 			return new Docker(serverConnectionBlob.server.docker);
	// 		});
	// 	// return Promise.promise(new Docker({socketPath:'/var/run/docker.sock'}));
	// }

	public static function createServerInstance(config :ProviderConfig) :Promise<InstanceDefinition>
	{
		trace('Creating ${config.type} ${Constants.APP_NAME} server');
		return switch(config.type) {
			case boot2docker:
				return Promise.promise(WorkerProviderBoot2Docker.getLocalDockerWorker());
			case vagrant:
				throw "This is currently broken";
				//TODO: this should be easy
				var path = Constants.SERVER_VAGRANT_DIR;//Path.join()
				// var id :MachineId = ComputeTools.createUniqueId();
				var address :IP = '192.168.' + Math.max(1, Math.floor(Math.random() * 254)) + '.' + Math.max(1, Math.floor(Math.random() * 254));
				// var vagrantPath = VagrantPath.from(Path.join(id), address);
				FsExtended.ensureDirSync(path);
				var streams :util.streams.StdStreams = {out:js.Node.process.stdout, err:js.Node.process.stderr};
				return WorkerProviderVagrantTools.ensureWorkerBox(path, address, null, streams)
				// return ccc.compute.workers.VagrantTools.ensureVagrantBoxRunning(path, streams)
					.pipe(function(vagrant) {
						return WorkerProviderVagrantTools.getWorkerDefinition(path);
						trace('vagrant=${vagrant}');
						return null;
					})
					.then(function(def) {
						trace('def=${def}');
						return def;
					});
				return Promise.promise(null);
			case pkgcloud:
				var provider = WorkerProviderTools.getProvider(cast config);
				// trace('provider=${provider}');
				trace('createIndependentWorker');
				return provider.createServer();
			default:
				return Promise.promise(null);
		}
	}

	// public static function isServerConfigStoredLocally() :Promise<Bool>
	// {
	// 	var base = Path.dirname(SERVER_CONNECTION_FILE);
	// 	return Promise.promise(FsExtended.existsSync(base) && FsExtended.existsSync(SERVER_CONNECTION_FILE));
	// }

	public static function isServerInstalled(serverDefinition :InstanceDefinition) :Promise<Bool>
	{
		var docker = new Docker(serverDefinition.docker);
		return DockerTools.getContainersByLabel(docker, APP_NAME_COMPACT)
			.then(function(containers) {
				Log.info({f:'getContainersByLabel', containers:containers});
				return containers.filter(function(c) return c.Status == DockerMachineStatus.Running).length > 0;
			});
	}

	inline public static function getServerHost(host :HostName) :Host
	{
		return new Host(host, new Port(SERVER_DEFAULT_PORT));
	}

	/**
	 * Installs the cloudcomputecannon.js server onto a provider.
	 * Assumes the ssh and docker processes are reachable.
	 * @param  server :ServerConfig [description]
	 * @return        [description]
	 */
	public static function installServer(serverBlob :ServerConnectionBlob, ?force :Bool = false, ?uploadOnly :Bool = false) :Promise<Bool>
	{
		var instance = serverBlob.server;
		return Promise.promise(true)
			.pipe(function(_) {
				js.Node.process.stdout.write('Checking for docker-compose...');
				return checkForDockerCompose(instance.ssh)
					.pipe(function(isInstalled) {
						if (isInstalled) {
							js.Node.process.stdout.write('installed\n');
							return Promise.promise(true);
						} else {
							js.Node.process.stdout.write('not installed...');
							return installDockerCompose(instance)
								.thenTrue();
						}
					});
			})
			//Check for the server docker container is running
			.pipe(function(_) {
				js.Node.process.stdout.write('Check for cloud-compute-cannon server running...');
				return checkServerRunning(instance)
					.pipe(function(ok) {
						if (ok && !force) {
							js.Node.process.stdout.write('confirmed running.\n');
							return Promise.promise(true);
						} else {
							if (ok && force) {
								js.Node.process.stdout.write('confirmed running, but forcing re-install...');
							} else {
								js.Node.process.stdout.write('not running, installing, first copy files...');
							}
							//Install the server via compose
							return Promise.promise(true)
								.pipe(function(_) {
									return copyFilesForRemoteServer(serverBlob);
								})
								.pipe(function(_) {
									if (uploadOnly) {
										return Promise.promise(true);
									} else {
										js.Node.process.stdout.write('starting server stack...');
										return runDockerComposedServer(instance.ssh);
									}
								});
						}
					});
			})
			.thenTrue();
	}

	/**
	 * Installs the cloudcomputecannon.js server onto a provider.
	 * Assumes the ssh and docker processes are reachable.
	 * @param  server :ServerConfig [description]
	 * @return        [description]
	 */
	public static function stopServer(serverBlob :ServerConnectionBlob) :Promise<Bool>
	{
		var instance = serverBlob.server;
		return Promise.promise(true)
			//Check for the server docker container is running
			.pipe(function(_) {
				js.Node.process.stdout.write('Stopping server...');
				return checkServerRunning(instance)
					.pipe(function(running) {
						if (!running) {
							js.Node.process.stdout.write('already stopped.\n');
							return Promise.promise(true);
						} else {
							return stopDockerComposedServer(instance)
								.then(function(_) {
									js.Node.process.stdout.write('stopped.\n');
									return true;
								});
						}
					});
			})
			.thenTrue();
	}

	public static function checkServerRunning(instance :InstanceDefinition, ?swallowErrors :Bool = true) :Promise<Bool>
	{
		var host = getServerHost(new HostName(instance.ssh.host));
		return ClientTools.isServerListening(host);
	}

	public static function serverCheck(serverBlob :ServerConnectionBlob) :Promise<ServerCheckResult>
	{
		var host = serverBlob.host;
		var instance = serverBlob.server;
		var result :ServerCheckResult = {
			ok: false,
			connection_file_path: null,
			status_check_success : {
				ssh: false,
				docker_compose: false,
				http_api: false
			},
			server_id: instance != null ? instance.id : '',
			server_host: host,
			http_api_url: '',
			error: null
		}

		return Promise.promise(true)
			.pipe(function(_) {
				if (instance != null) {
					return SshTools.getSsh(instance.ssh, 1, 0, null, null, true)
						.pipe(function(sshclient) {
							result.status_check_success.ssh = true;
							sshclient.end();
							return ProviderTools.checkForDockerCompose(instance.ssh)
								.then(function(isComposeInstalled) {
									result.status_check_success.docker_compose = isComposeInstalled;
									return true;
								});
						})
						.errorPipe(function(err) {
							result.status_check_success.ssh = false;
							return Promise.promise(true);
						});
				} else {
					return Promise.promise(true);
				}
			})
			.pipe(function(_) {
				if (host != null) {
					var url = 'http://$host/checks';
					result.http_api_url = 'http://${host}${SERVER_RPC_URL}';
					return RequestPromises.get(url, 200)
						.then(function(out) {
							result.status_check_success.http_api = out.trim() == SERVER_PATH_CHECKS_OK;
							return true;
						})
						.errorPipe(function(err) {
							result.error = err.code;
							return Promise.promise(true);
						});
				} else {
					result.error = 'FAIL: No server found! Either pass the address of the host with the -H parameter, or install a server in this or a parent directory,';
					return Promise.promise(true);
				}
			})
			.then(function(_) {
				if (serverBlob.server != null) {
					result.ok = result.status_check_success.ssh && result.status_check_success.http_api && result.status_check_success.docker_compose;
				} else {
					result.ok = result.status_check_success.http_api;
					Reflect.deleteField(result.status_check_success, 'ssh');
					Reflect.deleteField(result.status_check_success, 'docker_compose');
				}
				if (result.error == null) {
					Reflect.deleteField(result, 'error');
				}
				return result;
			});
	}

	/**
	 * Installs the cloudcomputecannon.js server onto a provider.
	 * @param  server :ServerConfig [description]
	 * @return        [description]
	 */
	static function installServerOLD(server :InstanceDefinition) :Promise<DockerContainer>
	{
		trace('creating new server docker context');
		var tmpBase = '$LOCAL_CONFIG_DIR/tmp'; //Os.tmpdir();
		var dockerDir = Path.join(tmpBase, 'serverdocker');
		trace('dockerDir=$dockerDir');
		try {//rm -rf $dockerDir
			FsExtended.deleteDirSync(dockerDir);
		} catch (err :Dynamic) {
			//Ignored
		}
		FsExtended.ensureDirSync(dockerDir);// mkdir -p $dockerDir

		for (resourceId in ['cloudcomputecannon.js', 'package.json', 'Dockerfile']) {
			Assert.that(haxe.Resource.getString(resourceId) != null, 'Missing resource $resourceId');
			FsExtended.writeFileSync(Path.join(dockerDir, resourceId), haxe.Resource.getString(resourceId));
		}

		var docker = new Docker(server.docker);

		//Ensure the other two containers (redis + registry)
		return promhx.Promise.whenAll(
			[
				util.DockerTools.ensureContainer(docker, 'redis:3', 'name', SERVER_CONTAINER_TAG_REDIS),
				util.DockerTools.ensureContainer(docker, 'registry:2', 'name', SERVER_CONTAINER_TAG_REGISTRY, null, [Constants.REGISTRY_DEFAULT_PORT=>REGISTRY_DEFAULT_PORT])
			])
		.pipe(function(_) {
			trace('Redis and registry containers running...');
			var tarStream = js.npm.tarfs.TarFs.pack(dockerDir);//Build docker image, create tar stream
			trace('building server docker image');
			//Perhaps incorporate a unique key, so that others cannot access the internal server
			return DockerTools.buildDockerImage(docker, APP_NAME_COMPACT, tarStream, null)
				.pipe(function(imageId) {
					trace('imageId=${imageId}');

					var createOpts :CreateContainerOptions = {
						name: 'cloudcomputecannon',
						Image: imageId,
						Cmd: ['node', 'cloudcomputecannon.js'],
						WorkingDir: '/app',
						Labels: {'name': 'cloudcomputecannon'},
						Env: [
							'${ENV_VAR_COMPUTE_CONFIG}=' + Yaml.render(InitConfigTools.ohGodGetConfigFromSomewhere())
						],
						HostConfig: {
							Links: [
								'$SERVER_CONTAINER_TAG_REDIS:redis',
								'$SERVER_CONTAINER_TAG_REGISTRY:registry'
							]
						}
					}
					var ports :Map<Int,Int> = [SERVER_DEFAULT_PORT=>9000];
					return DockerTools.createContainer(docker, createOpts, ports)
						.pipe(function(container) {
							return DockerTools.startContainer(container, null, ports)
								.then(function(success) {
									return container;
								});
						});
				});
		});
	}

	public static function checkForDockerCompose(sshConfig :ConnectOptions) :Promise<Bool>
	{
		//Test docker-compose
		return SshTools.execute(sshConfig, '/opt/bin/docker-compose --version')
			.then(function(execResult) {
				return execResult.code == 0;
			});
	}

	static function installDockerCompose(instance :InstanceDefinition) :Promise<InstanceDefinition>
	{
		var remoteScriptPath = '/tmp/install_docker_compose.sh';
		js.Node.process.stdout.write('...installing docker-compose');
		// trace('remoteScriptPath=${remoteScriptPath}');
		return Promise.promise(true)
			//Copy the docker-compose install script
			.pipe(function(_) {
				js.Node.process.stdout.write('...copying install script');
				Assert.notNull(Resource.getString(SERVER_INSTALL_COMPOSE_SCRIPT));
				return SshTools.writeFileString(instance.ssh, remoteScriptPath, Resource.getString(SERVER_INSTALL_COMPOSE_SCRIPT));
			})
			//Run the docker-compose script
			.pipe(function(_) {
				js.Node.process.stdout.write('...executing');
				return SshTools.execute(instance.ssh, 'sudo sh $remoteScriptPath');
			})
			.then(function(_) {
				js.Node.process.stdout.write('...done\n');
				return instance;
			});
	}

	static function runDockerComposedServer(ssh :ConnectOptions) :Promise<Bool>
	{
		var dc ="/opt/bin/docker-compose -f docker-compose.yml -f docker-compose.prod.yml";
		var command = 'cd ${Constants.APP_NAME_COMPACT} && $dc stop && $dc rm -fv && $dc build && $dc up -d';
		return SshTools.execute(ssh, command, 10, 10, null, null, true)
			.then(function(execResult) {
				if (execResult.code != 0) {
					throw execResult;
				}
				return true;
			});
	}

	static function stopDockerComposedServer(instance :InstanceDefinition) :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				//Docker stop
				return SshTools.execute(instance.ssh, 'cd ${Constants.APP_NAME_COMPACT} && sudo docker-compose stop')
					.then(function(execResult) {
						if (execResult.code != 0) {
							throw execResult;
						}
						return true;
					});
			});
	}

	static function runContainer(docker :Docker, imageId :ImageId) :Promise<DockerContainer>
	{
		Assert.notNull(docker);
		Assert.notNull(imageId);
		var promise = new DeferredPromise();
		imageId = imageId.toLowerCase();
		var volumes = {};
		var hostConfig :CreateContainerHostConfig = {};
		hostConfig.Binds = [];
		var labels :Dynamic<String> = {};
		Reflect.setField(labels, APP_NAME_COMPACT, '1');

		docker.createContainer({
			Image: imageId,
			// Cmd: cmd,
			AttachStdout: true,
			AttachStderr: true,
			Tty: false,
			Labels: labels,
			// Volumes: volumes,
			HostConfig: hostConfig,
			// WorkingDir: workingDir
		}, function(err, container) {
			if (err != null) {
				promise.boundPromise.reject(err);
				return;
			}
			container.attach({logs:true, stream:true, stdout:true, stderr:true}, function(err, stream) {
				if (err != null) {
					promise.boundPromise.reject(err);
					return;
				}
				untyped __js__('container.modem.demuxStream({0}, {1}, {2})', stream, Node.process.stdout, Node.process.stderr);
				container.start(function(err, data) {
					if (err != null) {
						promise.boundPromise.reject(err);
						return;
					}
				});
				stream.once('end', function() {
					promise.resolve(container);
				});
			});
		});
		return promise.boundPromise;
	}

	public static function copyFilesForRemoteServer(serverBlob :ServerConnectionBlob) :Promise<Bool>
	{
		if (serverBlob.provider == null) {
			var p = new Promise();
			p.reject('Missing serverBlob.provider');
			return p;
		}
		//Ensure the hostname
		Constants.SERVER_HOSTNAME_PUBLIC = serverBlob.server.hostPublic;
		Constants.SERVER_HOSTNAME_PRIVATE = serverBlob.server.hostPrivate;
		var instance = serverBlob.server;
		var storage = ccc.storage.ServiceStorageSftp.fromInstance(instance).appendToRootPath(Constants.APP_NAME_COMPACT);
		return Promise.promise(true)
			.pipe(function(_) {
				return storage.writeFile('$SERVER_MOUNTED_CONFIG_FILE_NAME', StreamTools.stringToStream(Json.stringify(serverBlob.provider, null, '\t')));
			})
			.pipe(function(_) {
				return copyServerFiles(storage);
			});
	}

	public static function copyFilesForLocalServer(path :String) :Promise<Bool>
	{
		var localStorage = ServiceStorageLocalFileSystem.getService(path);
		return ProviderTools.copyServerFiles(localStorage)
			.pipe(function(_) {
				var defaultServerConfigString = Yaml.render(InitConfigTools.getDefaultConfig());
				return localStorage.writeFile(SERVER_MOUNTED_CONFIG_FILE_NAME, StreamTools.stringToStream(defaultServerConfigString));
			})
			.pipe(function(_) {
				var promises = [
					'docker-compose.yml',
					'docker-compose.core.yml',
					'docker-compose.override.yml',
				].map(function(f) {
					return localStorage.writeFile(f, StreamTools.stringToStream(Resource.getString(f)));
				});
				return Promise.whenAll(promises);
			})
			.thenTrue();
	}

	static function generateFluentConfigFiles() :Map<String,String>
	{
		var map = new Map<String,String>();
		for (type in ['dev', 'prod']) {
			var base = 'etc/log/fluent.conf.base.template';
			var baseContent = new Template(Resource.getString(base)).execute(Constants);
			var inFile = 'etc/log/fluent.$type.conf.template';
			var inContent = Resource.getString(inFile);
			var outContent = new Template(inContent).execute(Constants);
			map['etc/log/fluent.$type.conf'] = baseContent + outContent;
		}
		return map;
	}

	static function copyServerFiles(storage :ServiceStorage) :Promise<Bool>
	{
		trace('...copying files to ${storage.toString()}...');
		return Promise.promise(true)
			//Copy non-template files first. Don't copy files that also have a template version
			.pipe(function(_) {
				var promises = [];
				var templates = Resource.listNames().filter(function(e) return e.endsWith('.template'));
				var nonTemplates = Resource.listNames().filter(function(e) return !e.endsWith('.template'));
				nonTemplates = nonTemplates.filter(function(e) {
					return !templates.has(e + '.template');
				});
				for (resourceName in nonTemplates) {
					var content = Resource.getString(resourceName);
					var name = resourceName.startsWith('etc/server/') ? resourceName.replace('etc/server/', '') : resourceName;
					var path = name;
					promises.push(function() {
						trace(path);
						return storage.writeFile(path, StreamTools.stringToStream(content));
					});
				}
				return PromiseTools.chainPipePromises(promises);
			})
			//Generate and copy the log templated files so they can overwrite existing files
			.pipe(function(_) {
				var promises = [];
				var logConfigFileMap = generateFluentConfigFiles();
				for (path in logConfigFileMap.keys()) {
					promises.push(function() {
						trace(path);
						return storage.writeFile(path, StreamTools.stringToStream(logConfigFileMap.get(path)));
					});
				}
				return PromiseTools.chainPipePromises(promises);
			})
			//Copy the templates afterwards so they overwrite non-template files
			.pipe(function(_) {
				var promises = [];
				var templates = Resource.listNames().filter(function(e) return e.endsWith('.template') && !e.startsWith('etc/log'));
				for (resourceName in templates) {
					var content = new haxe.Template(Resource.getString(resourceName)).execute(Constants);
					var name = resourceName.startsWith('etc/server/') ? resourceName.replace('etc/server/', '') : resourceName;
					name = name.substr(0, name.length - '.template'.length);
					var path = name;
					promises.push(function() {
						trace(path);
						return storage.writeFile(path, StreamTools.stringToStream(content));
					});
				}
				return PromiseTools.chainPipePromises(promises);
			})
			.then(function(_) {
				return true;
			})
			.thenTrue();
	}
}