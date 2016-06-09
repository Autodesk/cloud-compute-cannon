package util;

import haxe.Json;

import js.Node;
import js.node.Fs;
import js.node.stream.Readable;
import js.node.stream.Writable;
import js.npm.Docker;

import js.node.stream.Readable;
import js.node.stream.Writable;

import promhx.Promise;
import promhx.CallbackPromise;
import promhx.DockerPromises;
import promhx.RetryPromise;
import promhx.deferred.DeferredPromise;

import t9.abstracts.net.*;

using promhx.PromiseTools;
using Lambda;
using StringTools;

typedef Modem = {
	function demuxStream(stream :IReadable, out :IWritable, err :IWritable) :Void;
}

typedef DockerUrlBlob = {
	var name:String;
	@:optional var username :String;
	@:optional var registryhost :Host;
	@:optional var tag :String;
}

abstract DockerUrl(String) to String from String
{
	inline public function new (s :String)
		this = s;

	public var tag(get, set) :String;
	public var registryhost(get, set) :Host;
	public var username(get, set) :String;
	public var name(get, set) :String;
	public var repository(get, never) :String;

	inline public function noTag() :DockerUrl
	{
		var u = DockerTools.parseDockerUrl(this);
		u.tag = null;
		return DockerTools.joinDockerUrl(u);
	}

	inline public function get_repository() :String
	{
		var u = DockerTools.parseDockerUrl(this);
		u.tag = null;
		u.registryhost = null;
		return DockerTools.joinDockerUrl(u);
	}

	inline public function set_tag(tag :String) :String
	{
		var u = DockerTools.parseDockerUrl(this);
		u.tag = tag;
		this = DockerTools.joinDockerUrl(u);
		return tag;
	}

	inline public function get_tag() :String
	{
		var u = DockerTools.parseDockerUrl(this);
		return u.tag;
	}

	inline public function set_registryhost(registryhost :Host) :Host
	{
		var u = DockerTools.parseDockerUrl(this);
		u.registryhost = registryhost;
		this = DockerTools.joinDockerUrl(u);
		return tag;
	}

	inline public function get_registryhost() :Host
	{
		var u = DockerTools.parseDockerUrl(this);
		return u.registryhost;
	}

	inline public function set_username(username :String) :String
	{
		var u = DockerTools.parseDockerUrl(this);
		u.username = username;
		this = DockerTools.joinDockerUrl(u);
		return tag;
	}

	inline public function get_username() :String
	{
		var u = DockerTools.parseDockerUrl(this);
		return u.username;
	}

	inline public function set_name(name :String) :String
	{
		var u = DockerTools.parseDockerUrl(this);
		u.name = name;
		this = DockerTools.joinDockerUrl(u);
		return tag;
	}

	inline public function get_name() :String
	{
		var u = DockerTools.parseDockerUrl(this);
		return u.name;
	}
}

class DockerTools
{
	public static function joinDockerUrl(u :DockerUrlBlob, ?includeTag :Bool = true) :String
	{
		return (u.registryhost != null ? u.registryhost + '/' : '')
			+ (u.username != null ? u.username + '/' : '')
			+ u.name
			+ (u.tag != null && includeTag ? ':' + u.tag : '');
	}

	public static function getRepository(u :DockerUrlBlob, ?includeTag :Bool = true) :String
	{
		return (u.registryhost != null ? u.registryhost + '/' : '')
			+ (u.username != null ? u.username + '/' : '')
			+ u.name
			+ (u.tag != null && includeTag ? ':' + u.tag : '');
	}

	public static function parseDockerUrl(s :String) :DockerUrlBlob
	{
		s = s.trim();
		var r = ~/(.*\/)?([a-z0-9_]+)(:[a-z0-9_]+)?/i;
		r.match(s);
		var registryAndUsername = r.matched(1);
		var name = r.matched(2);
		var tag = r.matched(3);
		if (tag != null) {
			tag = tag.substr(1);
		}
		registryAndUsername = registryAndUsername != null ?registryAndUsername.substr(0, registryAndUsername.length - 1) : null;
		var username :String = null;
		var registryHost :Host = null;
		if (registryAndUsername != null) {
			var tokens = registryAndUsername.split('/');
			if (tokens.length > 1) {
				username = tokens.pop();
				registryHost = tokens.length > 0 ? tokens.join('/') : null;
			} else {
				registryHost = tokens.join('/');
			}
		}
		var url :DockerUrlBlob = {
			name: name
		}
		if (tag != null) {
			url.tag = tag;
		}
		if (username != null) {
			url.username = username;
		}
		if (registryHost != null) {
			url.registryhost = registryHost;
		}
		return url;
	}

	/**
	 * Given a docker image name (and optional tags) ensures
	 * that there is an image with that name and tag running.
	 * This can be used to link containers.
	 * @param  docker      :Docker       [description]
	 * @param  image       :String       [description]
	 * @param  ?labelKey   :String       [description]
	 * @param  ?labelValue :String       [description]
	 * @return             [description]
	 */
	public static function ensureContainer(docker :Docker, image :String, ?labelKey :String = 'name', ?labelValue :String = null, ?createOptions :CreateContainerOptions, ?ports :Map<Int,Int>) :Promise<DockerContainer>
	{
		labelValue = labelValue != null ? labelValue : image;
		return DockerPromises.listContainers(docker, {all:true, filters:DockerTools.createLabelFilter('$labelKey=$labelValue')})
			.pipe(function(containers) {
				//containers is an Array with objects like:
				// {
				// 	Id : b5eb3fc35e6d06797e021d93afce7e5a49b4b4e69fceae8395f2f926c77f26a5,
				// 	Names : [/tender_sammet],
				// 	Image : abb84f367f07,
				// 	ImageID : abb84f367f07be48f7e736eb7a6959f219d48c180dc65e3ec98b928d4a10845b,
				// 	Command : /bin/sh -c 'node $APP/cloudcomputecannon.js',
				// 	Created : 1457722629,
				// 	Ports : [],
				// 	Labels : {
				// 		cloudcomputecannon : 1
				// 	},
				// 	Status : Created,
				// 	HostConfig : {
				// 		NetworkMode : default
				// 	}
				// }
				var promises = [];
				var running :DockerContainer = null;
				if (containers.length > 0) {
					//Get perhaps one that isn't running, remove the rest
					var removeContainerPromises = containers.map(function(c) {
						var isRunning = c.Status == DockerMachineStatus.Running || Std.string(c.Status).startsWith('Up');
						if (isRunning && running == null) {
							running = docker.getContainer(c.Id);
							return Promise.promise(true);
						} else {
							return DockerTools.removeContainer(docker.getContainer(c.Id), false);
						}
					});
					promises = promises.concat(removeContainerPromises);
				}
				return Promise.whenAll(promises)
					.pipe(function(_) {
						if (running == null) {
							//Pull the image
							var createImageOptions = {
								fromImage: image
							}
							return getImage(docker, createImageOptions)
								.pipe(function(out) {
									var Labels = {};
									Reflect.setField(Labels, labelKey, labelValue);
									var opts :CreateContainerOptions = createOptions != null ? createOptions : {Image:null};
									Reflect.setField(opts, 'name', labelValue);
									Reflect.setField(opts, 'Image', image);
									Reflect.setField(opts, 'Labels', Labels);

									return createContainer(docker, opts, ports)
										.pipe(function(container) {
											return startContainer(container, null, ports)
												.then(function(success) {
													return container;
												});
										});
								});
						} else {
							return Promise.promise(running);
						}
					});
			});
	}

	public static function createDataVolumeContainer(docker :Docker, name :String, imageId :String, volumes :Array<String>, ?labels :Dynamic<String>) :Promise<DockerContainer>
	{
		//https://github.com/docker/docker/issues/15908
		var volumesObj = {};
		for (vol in volumes) {
			Reflect.setField(volumesObj, vol, {});
		}
		return DockerPromises.createContainer(docker, {
			Image: imageId,
			name: name,
			AttachStdout: false,
			AttachStderr: false,
			Volumes: volumesObj,
			Labels: labels
		});
	}

	public static function getContainersByLabel(docker :Docker, label :String) :Promise<Array<ContainerData>>
	{
		return DockerPromises.listContainers(docker, {all:true, filters:DockerTools.createLabelFilter(label)});
	}

	public static function sendStreamToDataVolumeContainer(data :IReadable, container :DockerContainer, path :String) :Promise<Bool>
	{
		var promise = new promhx.CallbackPromise();
		container.putArchive(data, {path:path}, promise.cb2);
		return promise
			.thenTrue();
	}

	public static function getStreamFromDataVolumeContainer(container :DockerContainer, path :String) :Promise<IReadable>
	{
		var promise = new promhx.CallbackPromise();
		container.getArchive({path:path}, promise.cb2);
		return promise;
	}

	public static function buildDockerImage(docker :Docker, id :String, image :IReadable, resultStream :IWritable, ?log :AbstractLogger) :Promise<ImageId>
	{
		return promhx.RetryPromise.pollDecayingInterval(__buildDockerImage.bind(docker, id, image, resultStream, log), 3, 100, 'DockerTools.buildDockerImage($id)');
	}

	public static function buildImageFromFiles(docker :Docker, imageId :String, fileData :Map<String,String>, resultStream :IWritable, ?log :AbstractLogger) :Promise<ImageId>
	{
		var tarStream = TarTools.createTarStreamFromStrings(fileData);
		return buildDockerImage(docker, imageId, tarStream, resultStream, log);
	}

	public static function __buildDockerImage(docker :Docker, id :String, image :IReadable, resultStream :IWritable, ?log :AbstractLogger) :Promise<ImageId>
	{
		log = Logger.ensureLog(log, {f:'buildDockerImage'});
		log = log.child({image:id, dockerhost:docker.modem.host});
		var promise = new DeferredPromise();
		log.info('build_image');
		docker.buildImage(image, {t:id}, function(err, stream: IReadable) {
			if (err != null) {
				log.error({log:'Error on building image', error:err});
				promise.boundPromise.reject(err);
				return;
			}
			var errorEncounteredInStream = false;
			var mostRecentError;
			var imageId :ImageId = null;
			var bufferString :String = '';

			stream.once(ReadableEvent.End, function() {
				if (!promise.isResolved()) {
					if (errorEncounteredInStream) {
						promise.boundPromise.reject(err);
					} else {
						promise.resolve(imageId);
					}
				}
			});
			stream.once(ReadableEvent.Error, function(err) {
				log.error({log:'Error on building image', type:'readable_stream_error', error:err});
				promise.boundPromise.reject(err);
			});
			stream.on(ReadableEvent.Data, function(buf :js.node.Buffer) {
				if (resultStream != null && buf != null) {
					resultStream.write(buf);
				}
				if (buf != null) {
					var bufferString = buf.toString();
					var data :ResponseStreamObject;
					try {
						data = Json.parse(bufferString);
					} catch (err :Dynamic) {
						log.error({log:'Maybe not the end of the world, but cannot json parse bufferString', data:bufferString, error:err});
						return;
					}
					if (data.stream != null) {
						// log.trace({log:data.stream});
						if (data.stream.startsWith('Successfully built')) {
							imageId = data.stream.replace('Successfully built', '').trim();
						}
					} else if (data.status != null) {
						// log.trace({log:bufferString});
					} else if (data.error != null) {
						log.error({log:'Stream data contains an error entry', data:bufferString, error:data.error});
						errorEncounteredInStream = true;
						mostRecentError = data;
					} else {
						log.warn({log:'Cannot handle stream data', data:bufferString});
					}
				}
			});
		});
		return promise.boundPromise;
	}

	public static function pushImage(docker :Docker, imageName :String, ?tag :String, ?resultStream :IWritable, ?log :AbstractLogger) :Promise<Bool>
	{
		return promhx.RetryPromise.pollDecayingInterval(__pushImage.bind(docker, imageName, tag, resultStream, log), 3, 100, 'DockerTools.pushImage(imageName=$imageName)');
	}

	public static function pullImage(docker :Docker, imageName :String, ?opts :Dynamic, ?type :PollType, ?retries :Int = 3, ?interval :Int = 100, ?log :AbstractLogger) :Promise<Array<Dynamic>>
	{
		type = type == null ? PollType.regular : type;
		return RetryPromise.poll(__pullImage.bind(docker, imageName, opts, log), type, retries, interval, 'DockerTools.pullImage(imageName=$imageName)');
	}

	public static function __pushImage(docker :Docker, imageName :String, ?tag :String, ?resultStream :IWritable, ?log :AbstractLogger) :Promise<Bool>
	{
		log = Logger.ensureLog(log, {image:imageName, tag:tag, dockerhost:docker.modem.host});
		var promise = new DeferredPromise();
		var image = docker.getImage(imageName);
		image.push({tag:tag}, function(err, stream :IWritable) {
			if (err != null) {
				log.error({log:'error pushing $imageName', error:err});
				promise.boundPromise.reject(err);
				return;
			}
			stream.on(ReadableEvent.End, function() {
				promise.resolve(true);
			});
			stream.on(ReadableEvent.Error, function(err) {
				promise.boundPromise.reject(err);
			});
			stream.on(ReadableEvent.Data, function(buf :js.node.Buffer) {
				if (resultStream != null && buf != null) {
					resultStream.write(buf);
				}
				var bufferString = buf.toString();
				// log.trace({log:bufferString});
			});
		});
		return promise.boundPromise;
	}

	static function __pullImage(docker :Docker, repoTag :String, ?opts :Dynamic, ?log :AbstractLogger) :Promise<Array<Dynamic>>
	{
		log = Logger.ensureLog(log, {image:repoTag, tag:tag, dockerhost:docker.modem.host, f:'__pullImage'});
		var promise = new DeferredPromise();
		docker.pull(repoTag, opts, function(err, stream) {
			if (err != null) {
				promise.boundPromise.reject({error:err, log:'docker.pullImage', repoTag:repoTag});
				return;
			}
			function onFinished(finishedErr, output) {
				if (finishedErr != null) {
					promise.boundPromise.reject({error:finishedErr, log:'docker.pullImage', repoTag:repoTag});
					return;
				}
				promise.resolve(output);
			}
			function onProgress(e) {
				log.debug(e);
			}
			docker.modem.followProgress(stream, onFinished, onProgress);
		});
		return promise.boundPromise;
	}

	public static function getImage(docker :Docker, opts :CreateImageOptions, ?log :AbstractLogger) :Promise<Bool>
	{
		log = Logger.ensureLog(log);
		log = log.child({opts:opts, dockerhost:docker.modem.host});
		var promise = new DeferredPromise();
		docker.createImage(null, opts, function(err, stream) {
			if (err != null) {
				log.error({log:'Error on getting image', error:err});
				promise.boundPromise.reject(err);
				return;
			}
			var errorEncounteredInStream = false;
			var mostRecentError = null;
			var imageId :ImageId = null;
			stream.once(ReadableEvent.End, function() {
				if (errorEncounteredInStream) {
					promise.boundPromise.reject(mostRecentError);
				} else {
					promise.resolve(true);
				}
			});
			stream.once(ReadableEvent.Error, function(err) {
				log.error({log:'Error on getting image', error:err});
				promise.boundPromise.reject(err);
			});
			stream.on(ReadableEvent.Data, function(buf :js.node.Buffer) {
				if (buf != null) {
					var bufferString = buf.toString();
					bufferString = bufferString.replace('\\"', '"');
					try {
						var data :ResponseStreamObject = Json.parse(bufferString);
						if (data.stream != null) {
							log.trace({log:data.stream});
							if (data.stream.startsWith('Successfully built')) {
								imageId = data.stream.replace('Successfully built', '').trim();
							}
						} else if (data.status != null) {
							log.trace({log:bufferString});
						} else if (data.error != null) {
							log.error({log:'Error on stream getting image', error:data});
							errorEncounteredInStream = true;
							mostRecentError = data;
						} else {
							log.warn({log:'Cannot handle stream data', data:data});
						}
					} catch (err :Dynamic) {
						log.error({log:'Cannot JSON.parse bufferString', error:err, data:bufferString});
					}
				}
			});
		});
		return promise.boundPromise;
	}

	public static function createContainer(docker :Docker, opts :CreateContainerOptions, ?ports :Map<Int,Int>) :Promise<DockerContainer>
	{
		addExposedPortsToContainerCreation(opts, ports);
		return DockerPromises.createContainer(docker, opts)
			.then(function(container) {
				if (ports != null) {
					Reflect.setField(container, 'ports', ports);
				}
				return container;
			});
	}

	public static function addExposedPortsToContainerCreation(opts :CreateContainerOptions, ports :Map<Int,Int>)
	{
		//https://groups.google.com/forum/#!searchin/docker-user/port$20redirection/docker-user/aHbNFACcTfs/nLY-oUihEAIJ
		var exposedPortsObj :TypedDynamicObject<String, {}>;
		if (ports != null) {
			exposedPortsObj = {};
			for (port in ports.keys()) {
				exposedPortsObj['${port}/tcp'] = {};
				// exposedPortsObj['${port}/tcp'] = [{HostPort:Std.string(ports[port])}];
			}
			// trace('exposedPortsObj=${exposedPortsObj}');
			opts.ExposedPorts = exposedPortsObj;

			if (!Reflect.hasField(opts, 'HostConfig')) {
				opts.HostConfig = {};
			}
			if (!Reflect.hasField(opts.HostConfig, 'PortBindings')) {
				untyped opts.HostConfig.PortBindings = {};
			}
			for (port in ports.keys()) {
				Reflect.setField(untyped opts.HostConfig.PortBindings, '$port/tcp', [{ 'HostPort': '' + ports[port] }]);
			}
		}
	}

	public static function startContainer(container :DockerContainer, ?opts :StartContainerOptions, ?ports :Map<Int,Int>) :Promise<DockerContainer>
	{
		var promise = new promhx.CallbackPromise();

		if (ports == null) {
			ports = Reflect.field(container, 'ports');
		}

		// https://groups.google.com/forum/#!searchin/docker-user/port$20redirection/docker-user/aHbNFACcTfs/nLY-oUihEAIJ
		if (ports != null) {
			if (opts == null) {
				opts = {};
			}
			if (opts.PortBindings == null) {
				opts.PortBindings = {}
			}
			for (port in ports.keys()) {
				Reflect.setField(opts.PortBindings, '${port}/tcp', [{HostPort:Std.string(ports[port])}]);
			}
		}
		container.start(opts, promise.cb2);
		return promise
			.thenVal(container);
	}

	public static function writeContainerLogs(container :DockerContainer, stdout :IWritable, stderr :IWritable) :Promise<Bool>
	{
		var promise = new DeferredPromise();

		container.logs({stdout:true, stderr:true}, function(err, stream) {
			if (err != null) {
				promise.boundPromise.reject(err);
				return;
			}
			stream.once(ReadableEvent.Error, function(err) {
				Log.error(err);
				promise.boundPromise.reject(err);
			});
			var modem :Modem = untyped __js__('container.modem');
			modem.demuxStream(stream, stdout, stderr);

			stream.once(ReadableEvent.End, function() {
				var stdoutFinished = false;
				var stderrFinished = false;
				function check() {
					if (stdoutFinished && stderrFinished) {
						promise.resolve(true);
					}
				}

				stdout.on(WritableEvent.Finish, function() {
					stdoutFinished = true;
					check();
				});
				stderr.on(WritableEvent.Finish, function() {
					stderrFinished = true;
					check();
				});

				stdout.end();
				stderr.end();
			});
		});

		return promise.boundPromise;
	}

	public static function removeAll(docker :Docker, containers :Array<ContainerData>) :Promise<Bool>
	{
		return Promise.whenAll(containers.filter(isRunning).map(function(c) return DockerPromises.stopContainer(docker.getContainer(c.Id))).array())
			.pipe(function(_) {
				return Promise.whenAll(containers.map(function(c) return DockerPromises.removeContainer(docker.getContainer(c.Id))).array());
			})
			.thenTrue();
	}

	public static function removeContainer(container :DockerContainer, ?suppressErrorIfContainerNotFound :Bool = false) :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				return DockerPromises.stopContainer(container);
			})
			.errorPipe(function(err) {
				//Container ${container.id} was probably stopped in between asking if it was stopped, and then sending the stop request
				return Promise.promise(true);
			})
			.pipe(function(_) {
				var p :Promise<Bool> = DockerPromises.removeContainer(container);
				if (suppressErrorIfContainerNotFound) {
					p = p.errorPipe(function(err) {
						Log.error('Container ${container.id} failed removal.');
						Log.error(err);
						return Promise.promise(true);
					});
				}
				return p;
			});
	}

	public static function createContainerDisposer(container :DockerContainer) :{dispose:Void->Promise<Bool>}
	{
		return {
			dispose: function() {
				return DockerPromises.stopContainer(container)
					.errorPipe(function(err) {
						Log.error({error:err, log:'Container ${container.id} was probably stopped inbetween asking if it was stopped, and then sending the stop request'});
						return Promise.promise(true);
					})
					.pipe(function(_) {
						return DockerPromises.removeContainer(container)
							.errorPipe(function(err) {
								Log.error({error:err, log:'Container ${container.id} failed removal.'});
								return Promise.promise(true);
							});
					});
			}
		};
	}

	public static function listImages(docker :Docker) :Promise<Array<ImageData>>
	{
		var promise = new CallbackPromise();
		docker.listImages(promise.cb2);
		return promise;
	}

	public static function tag(image :DockerImage, opts :DockerImageTagOptions) :Promise<Dynamic>
	{
		var promise = new CallbackPromise();
		image.tag(opts, promise.cb2);
		return promise;
	}

	public static function isRunning(c :ContainerData)
	{
		var t = switch(c.Status) {
			case Created,Exited: false;
			case Running,Restarting,Paused: true;
			default:
				return Std.string(c.Status).startsWith('Up');
		};
		Log.info('isRunning ? ${c.Id} ${c.Status} $t');
		return t;
	}

	//For docker.listContainers
	public static function createLabelFilter(labelKey :String)
	{
		return Json.stringify({label:[labelKey]});
	}
}