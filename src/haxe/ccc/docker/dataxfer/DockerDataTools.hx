package ccc.docker.dataxfer;

/**
 * -D DockerDataToolsDebug for extra logging
 */
import haxe.DynamicAccess;

import js.node.stream.Duplex;
import js.node.stream.Readable;
import js.node.stream.Writable;
import js.node.Fs;
import js.node.Path;

import js.npm.docker.Docker;
import js.npm.tarstream.TarStream;
import js.npm.tarfs.TarFs;

import promhx.deferred.*;
import promhx.Promise;
import promhx.Stream;
import promhx.StreamPromises;

import promhx.DockerPromises;

import util.streams.StreamTools;

enum DataTransferType {
	S3;
	Rsync;
	Sftp;
	Local;
}

typedef DockerVolumeDef = {
	@:optional var dockerOpts :DockerConnectionOpts;
	@:optional var docker :Docker;
	var name :DockerVolumeName;
}

typedef MountedDockerVolumeDef = {>DockerVolumeDef,
	/* Container mount point */
	@:optional var mount :String;
	/* This path refers to a sub path inside a docker container */
	@:optional var path :String;
}

typedef DataTransferOp = {
	var type :DataTransferType;
	var command :RunDockerCommand;
}

typedef CopyDataResult = {
	var end :Promise<DockerRunResult>;
	@:optional var progress :Stream<Float>;
}

typedef RunDockerCommand = {
	var command :Array<String>;
	var env :DynamicAccess<String>;
	var image :String;
}

typedef S3Credentials = {
	var keyId :String;
	var key :String;
	var bucket :String;
	@:optional var region :String;
	@:optional var path :String;
	@:optional var extraS3SyncParameters :Array<Array<String>>;
}


typedef DockerRunResult = {
	var StatusCode :Int;
	@:optional var stdout :String;
	@:optional var stderr :String;
	@:optional var error :Dynamic;
}

class DockerDataTools
{
	inline public static var AWS_CLI_IMAGE = 'docker.io/garland/aws-cli-docker';

	public static function lsVolume(volume :MountedDockerVolumeDef, ?path :String) :Promise<Array<String>>
	{
		Assert.notNull(volume);
		var docker = volume.docker != null ? volume.docker : new Docker(volume.dockerOpts);
		volume.mount = VOLUME_MOUNT_POINT1;
		if (path != null) {
			volume.mount = Path.join(volume.mount, path);
		}
		return runImageGetStdOut(docker, DOCKER_IMAGE_DEFAULT, ["find", volume.mount, "-type", "f"], [volume])
			.then(function(stdout) {
				return stdout != null ? stdout.trim().split('\n').map(function(s) return s.substr(VOLUME_MOUNT_POINT1.length + 1)): [];
			});
	}

	public static function transferVolumeToDisk(volume :MountedDockerVolumeDef, path :String) :Promise<DockerRunResult>
	{
		Assert.notNull(path);
		Assert.notNull(volume);

		return getData(volume, volume.path)
			.pipe(function(result) {
				var writableStream = TarFs.extract(path);
				return StreamPromises.pipe(result.stream, writableStream)
					.pipe(function(_) {
						return result.disposed;
					})
					.then(function(_) {
						var result :DockerRunResult = {StatusCode:0};
						return result;
					});
			});
	}

	public static function transferDiskToVolume(path :String, volume :MountedDockerVolumeDef) :Promise<DockerRunResult>
	{
		Assert.notNull(path);
		Assert.notNull(volume);

		try {
			Fs.accessSync(path);
		} catch(err :Dynamic) {
			return PromiseTools.error(err);
		}

		var readableTarStream = TarFs.pack(path);
		return addData(volume, readableTarStream, volume.path)
			.then(function(_) {
				var result :DockerRunResult = {StatusCode:0};
				return result;
			});
	}

	/* these functions are dumb and misleading, since it is confusing what
	happens when in or not in a container.
	*/
	public static function transferLocalDiskToLocalVolume(path :String, volume :MountedDockerVolumeDef) :CopyDataResult
	{
		return transferLocalDiskLocalVolume(volume, path, true);
	}

	public static function transferLocalVolumeToLocalDisk(volume :MountedDockerVolumeDef, path :String) :CopyDataResult
	{
		return transferLocalDiskLocalVolume(volume, path, false);
	}

	static function transferLocalDiskLocalVolume(volume :MountedDockerVolumeDef, path :String, fromDisk :Bool) :CopyDataResult
	{
		Assert.notNull(path);
		Assert.notNull(volume);

		path = Path.resolve(path);

		volume.mount = '$VOLUME_MOUNT_POINT1';

		var hostVolume :MountedDockerVolumeDef = {
			dockerOpts: volume.dockerOpts,
			docker: volume.docker,
			name: path,
			mount: VOLUME_MOUNT_POINT2
		}

		var volumePath = VOLUME_MOUNT_POINT2 + (volume.path != null ? '/${volume.path}' : '');

		var sourceUri = fromDisk ? volumePath : VOLUME_MOUNT_POINT1;
		var targetUri = fromDisk ? VOLUME_MOUNT_POINT1 : volumePath;
		if (!sourceUri.endsWith('/')) {
			sourceUri = sourceUri + '/';
		}
		if (!targetUri.endsWith('/')) {
			targetUri = targetUri + '/';
		}
		var op :DataTransferOp = {
			type: DataTransferType.Local,
			command: {
				command: ['cp', '--recursive', '--dereference', sourceUri + '.', targetUri],
				image: DOCKER_IMAGE_DEFAULT,
				env: {}
			}
		};
		return volumeOperation(op, [volume, hostVolume]);
	}

	public static function transferS3ToVolume(source :S3Credentials, volume :MountedDockerVolumeDef) :CopyDataResult
	{
		return transferS3Volume(volume, source, true);
	}

	public static function transferVolumeToS3(volume :MountedDockerVolumeDef, target :S3Credentials) :CopyDataResult
	{
		return transferS3Volume(volume, target, false);
	}

	static function transferS3Volume(volume :MountedDockerVolumeDef, credentials :S3Credentials, fromS3 :Bool) :CopyDataResult
	{
		Assert.notNull(credentials);
		Assert.notNull(credentials.bucket);
		Assert.notNull(credentials.keyId);
		Assert.notNull(credentials.key);
		Assert.notNull(volume);
		var internalContainerVolumePath = volume.path == null || volume.path == '/' || volume.path == '' ? VOLUME_MOUNT_POINT1 : Path.join(VOLUME_MOUNT_POINT1, (volume.path.startsWith('/') ? volume.path.substr(1) : volume.path));
		var targetPath = credentials.path == null ? '' : (credentials.path.startsWith('/') ? credentials.path.substr(1) : credentials.path);
		var sourceUri = fromS3 ? 's3://${credentials.bucket}/${targetPath}' : internalContainerVolumePath;
		var targetUri = fromS3 ? internalContainerVolumePath : 's3://${credentials.bucket}/${targetPath}';

		if (credentials.extraS3SyncParameters != null && credentials.extraS3SyncParameters.length > 0) {
			var promises = [];

			for (copyCommand in credentials.extraS3SyncParameters) {
				var command = ['aws', 's3', 'sync', sourceUri, targetUri].concat(copyCommand);
				var op :DataTransferOp = {
					type: DataTransferType.S3,
					command: {
						command: command,
						env: {
							AWS_ACCESS_KEY_ID: credentials.keyId,
							AWS_SECRET_ACCESS_KEY: credentials.key,
							AWS_DEFAULT_REGION: credentials.region != null ? credentials.region : 'us-west-1',
						},
						image: AWS_CLI_IMAGE
					}
				};
				volume.mount = VOLUME_MOUNT_POINT1;
				promises.push(volumeOperation(op, [volume]).end);
			}

			var result :CopyDataResult = {
				end: Promise.whenAll(promises)
					.then(function(allresults) {
						var finalResult :DockerRunResult = {
							StatusCode: allresults.fold(function(result, first :Int) {
								if (result.StatusCode != 0) {
									return result.StatusCode;
								} else {
									return first;
								}
							}, 0),
							stdout: allresults.fold(function(result, first :String) {
								if (first != null) {
									return first;
								} else if (result.stdout != null) {
									return allresults.map(function(e) return e.stdout).array().join(',');
								} else {
									return null;
								}
							}, null),
							stderr: allresults.fold(function(result, first :String) {
								if (first != null) {
									return first;
								} else if (result.stderr != null) {
									return allresults.map(function(e) return e.stderr).array().join(',');
								} else {
									return null;
								}
							}, null)
						};
						return finalResult;
					})
			}
			return result;
		} else {
			var op :DataTransferOp = {
				type: DataTransferType.S3,
				command: {
					command: ['aws', 's3', 'sync', sourceUri, targetUri],
					env: {
						AWS_ACCESS_KEY_ID: credentials.keyId,
						AWS_SECRET_ACCESS_KEY: credentials.key,
						AWS_DEFAULT_REGION: credentials.region != null ? credentials.region : 'us-west-1',
					},
					image: AWS_CLI_IMAGE
				}
			};
			volume.mount = VOLUME_MOUNT_POINT1;
			return volumeOperation(op, [volume]);
		}
	}

	public static function s3ls(docker :Docker, credentials :S3Credentials, path :String) :Promise<Array<String>>
	{
		Assert.notNull(credentials);
		Assert.notNull(credentials.bucket);
		Assert.notNull(credentials.keyId);
		Assert.notNull(credentials.key);

		var env = {
			AWS_ACCESS_KEY_ID: credentials.keyId,
			AWS_SECRET_ACCESS_KEY: credentials.key,
			AWS_DEFAULT_REGION: credentials.region != null ? credentials.region : 'us-west-1',
		};

		if (path.startsWith('/')) {
			path = path.substr(1);
		}
		var sourceUri = 's3://${credentials.bucket}/${path}';

		var command = ['aws', 's3', 'ls', sourceUri, '--recursive'];
		return runDockerCommand(docker, AWS_CLI_IMAGE, command, env)
			.then(function(result) {
				if (result.stdout != null) {
					var lines = result.stdout.split('\n').filter(function(s) return s.indexOf(path) > -1).map(function(s) return s.substr(s.indexOf(path)).trim()).array();
					return lines;
				} else {
					return [];
				}
			});
	}

	public static function runAwsCLI(docker :Docker, credentials :S3Credentials, command :Array<String>, ?volumes :Array<MountedDockerVolumeDef>, ?outStream :IWritable, ?errStream :IWritable) :Promise<DockerRunResult>
	{
		Assert.notNull(credentials);
		Assert.notNull(credentials.bucket);
		Assert.notNull(credentials.keyId);
		Assert.notNull(credentials.key);

		var env = {
			AWS_ACCESS_KEY_ID: credentials.keyId,
			AWS_SECRET_ACCESS_KEY: credentials.key,
			AWS_DEFAULT_REGION: credentials.region != null ? credentials.region : 'us-west-1',
		};

		return runDockerCommand(docker, AWS_CLI_IMAGE, command, env, volumes, outStream, errStream);
	}

	public static function runDockerCommand(docker :Docker, image :String, command :Array<String>, ?env :haxe.DynamicAccess<String>, ?volumes :Array<MountedDockerVolumeDef>, ?outStream :IWritable, ?errStream :IWritable) :Promise<DockerRunResult>
	{
		var result :DockerRunResult = {
			StatusCode: null,
			stdout: null,
			stderr: null,
			error: null
		}
		var promise = new DeferredPromise();
#if DockerDataToolsDebug
		outStream = outStream == null ? Node.process.stdout : outStream;
		errStream = errStream == null ? Node.process.stderr : errStream;
#else
		outStream = outStream == null ? Node.require('dev-null')() : outStream;
		errStream = errStream == null ? Node.require('dev-null')() : errStream;
#end
		var createOptions :CreateContainerOptions = {
			Image: image,
			HostConfig: {},
			Env: env != null ? env.keys().map(function(key) return '${key}=${env[key]}') : null,
			Tty: true//needed for splitting stdout/err
		}

		if (volumes != null) {
			createOptions.HostConfig.Binds = [];
			for (volume in volumes) {
				Assert.notNull(volume.name);
				Assert.notNull(volume.mount);
				createOptions.HostConfig.Binds.push('${volume.name}:${volume.mount}');
			}
		}

		var startOptions :StartContainerOptions = {};


		var outBuffer = new StringBuf();
		var grabberOutStream = StreamTools.createTransformStream(function(s) {
			outBuffer.add(s);
			return s;
		});
		grabberOutStream.pipe(outStream);

		var errBuffer = new StringBuf();
		var grabberErrStream = StreamTools.createTransformStream(function(s) {
			errBuffer.add(s);
			return s;
		});
		grabberErrStream.pipe(errStream);

		return DockerPromises.ensureImage(docker, createOptions.Image)
			.pipe(function(_) {

				var promise = new DeferredPromise();

#if DockerDataToolsDebug
				traceMagenta('command=${op.command.command} createOptions=${createOptions} startOptions=${startOptions}');
#end
				docker.run(image, command, [grabberOutStream, grabberErrStream], createOptions, startOptions, function(err, dataRun, container) {
#if DockerDataToolsDebug
					traceMagenta('docker run result err=$err data=$dataRun');
					traceCyan('volumeOperation created container=${container.id}');
#end

					result.StatusCode = dataRun != null ? dataRun.StatusCode : null;
					result.stdout = outBuffer.toString() != "" ? outBuffer.toString() : null;
					result.stderr = errBuffer.toString() != "" ? errBuffer.toString() : null;
					if (err != null) {
						traceRed('Error in docker run err=${Json.stringify(err)}');
						result.error = err;
						promise.boundPromise.reject(result);
						return;
					}
					if (container != null) {
						container.remove(function(errRemove, dataRemove) {
	#if DockerDataToolsDebug
							traceCyan('volumeOperation removed container=${container.id} errRemove=$errRemove data=$dataRemove');
	#end
							if (promise != null) {
								if (err != null) {
	#if DockerDataToolsDebug
									traceRed(err);
	#end
									result.error = err;
									promise.boundPromise.reject(result);
								} else if (dataRun.StatusCode != 0) {
	#if DockerDataToolsDebug
									traceRed('Non-zero StatusCode data:$dataRun');
	#end
									result.error = 'Non-zero StatusCode data:$dataRun';
									promise.boundPromise.reject(result);
								} else {
									promise.resolve(result);
								}
								promise = null;
							}
						});
					} else {
						result.error = 'No container';
						promise.boundPromise.reject(result);
					}
				})
				.on('container', function (container) {
				})
				.on('stream', function (stream) {
				})
				.on('data', function (data) {
				});

				return promise.boundPromise;
			});
	}

	public static function volumeOperation(op :DataTransferOp, volumes :Array<MountedDockerVolumeDef>, ?outStream :IWritable, ?errStream :IWritable) :CopyDataResult
	{
#if DockerDataToolsDebug
		outStream = outStream == null ? js.Node.process.stdout : outStream;
		errStream = errStream == null ? js.Node.process.stderr : errStream;
#else
		outStream = outStream == null ? Node.require('dev-null')() : outStream;
		errStream = errStream == null ? Node.require('dev-null')() : errStream;
#end
		var promise = new DeferredPromise();
		var finalResult  = {end:promise.boundPromise};
		Assert.that(volumes[0].docker != null || volumes[0].dockerOpts != null);
		var docker = volumes[0].docker != null ? volumes[0].docker : new Docker(volumes[0].dockerOpts);


		return {end:runDockerCommand(docker, op.command.image, op.command.command, op.command.env, volumes, outStream, errStream)};
	}

	public static function ensureEmptyDockerImage(docker :Docker) :Promise<Bool>
	{
		return DockerPromises.ensureImage(docker, EMPTY_DOCKER_IMAGE);
	}

	public static function createVolumeWithData(volume :DockerVolumeDef, tarStream :IReadable, ?opts :CreateVolumeOpts, ?parentDirPrefix :String = null) :Promise<DockerVolumeDef>
	{
		return createVolume(volume, opts)
			.pipe(function(_) {
				return addData(volume, tarStream, parentDirPrefix);
			});
	}

	public static function createVolume(volume :DockerVolumeDef, ?opts :CreateVolumeOpts) :Promise<DockerVolumeDef>
	{
		var promise = new DeferredPromise();
		var docker = volume.docker != null ? volume.docker : new Docker(volume.dockerOpts);
		opts = opts == null ? {} : opts;
		opts.Name = volume.name;

		docker.createVolume(opts, function(err) {
#if DockerDataToolsDebug
			traceCyan('createVolume ${volume.name}');
#end
			if (err != null) {
				promise.boundPromise.reject(err);
			} else {
				promise.resolve(volume);
			}
		});

		return promise.boundPromise;
	}

	public static function addData(volume :DockerVolumeDef, tarStream :IReadable, ?parentDirPrefix :String = null) :Promise<DockerVolumeDef>
	{
		var docker = volume.docker != null ? volume.docker : new Docker(volume.dockerOpts);

		return ensureEmptyDockerImage(docker)
			.pipe(function(_) {
				var promise = new DeferredPromise();

				//Create minimal container and mount the volume, then copy the data in
				var createOpts : CreateContainerOptions = {
					Image: EMPTY_DOCKER_IMAGE,
					HostConfig: {
						Binds: [
							'${volume.name}:${VOLUME_MOUNT_POINT1}:rw'
						]
					}
				}
				docker.createContainer(createOpts, function(createErr, container) {
#if DockerDataToolsDebug
					traceCyan('addData created container ${container.id} createErr=$createErr');
#end
					if (createErr != null) {
						promise.boundPromise.reject(createErr);
					} else {
						var putDataOpts = {
							path: VOLUME_MOUNT_POINT1,
							noOverwriteDirNonDir: 'true'
						}

						if (parentDirPrefix != null) {

							var extract = TarStream.extract();
							var pack = TarStream.pack();

							extract.on('entry', function(header, stream, callback :Null<js.Error>->Void) {
								// let's prefix all names with parentDirPrefix
								header.name = Path.join(parentDirPrefix, header.name);
								// write the new entry to the pack stream
								stream.pipe(pack.entry(header, callback));
							});

							extract.on('finish', function() {
								// all entries done - lets finalize it
								pack.finalize();
							});

							// pipe the old tarball to the extractor
							tarStream.pipe(extract);

							// pipe the new tarball the another stream
							tarStream = pack;
						}

						container.putArchive(tarStream, putDataOpts, function(putErr, data) {
							container.remove({force:true, v:true}, function(errRemove, data) {
#if DockerDataToolsDebug
								traceCyan('addData removed container ${container.id} errRemove=$errRemove');
#end
								if (putErr != null) {
									promise.boundPromise.reject(putErr);
								} else {
									if (errRemove != null) {
										promise.boundPromise.reject(errRemove);
									} else {
										promise.resolve(volume);
									}
								}
							});
						});
					}
				});
				return promise.boundPromise;
			});
	}

	public static function getData(volume :DockerVolumeDef, ?subDirectory :String) :Promise<{stream:IReadable, disposed:Promise<Bool>}>
	{
		var docker = volume.docker != null ? volume.docker : new Docker(volume.dockerOpts);

		subDirectory = subDirectory == null ? '/.' : subDirectory;
		subDirectory = !subDirectory.startsWith('/') ? '/' + subDirectory : subDirectory;
		subDirectory = subDirectory.endsWith('/') ? subDirectory + '.' : subDirectory;
		subDirectory = !subDirectory.endsWith("/.") ? subDirectory + "/." : subDirectory;

		return ensureEmptyDockerImage(docker)
			.pipe(function(_) {
				var promise = new DeferredPromise();

				//Create minimal container and mount the volume, then copy the data out
				var createOpts : CreateContainerOptions = {
					Image: EMPTY_DOCKER_IMAGE,
					HostConfig: {
						Binds: [
							'${volume.name}:${VOLUME_MOUNT_POINT1}'
						]
					}
				}

				docker.createContainer(createOpts, function(createErr, container) {
#if DockerDataToolsDebug
					traceCyan('getData createContainer ${container.id} createErr=$createErr');
#end
					if (createErr != null) {
						promise.boundPromise.reject(createErr);
					} else {
						var getDataOpts = {
							path: '${VOLUME_MOUNT_POINT1}${subDirectory}',
						}

						var cleanupPromise = new DeferredPromise();
						var isCleanedUp = false;
						function cleanupContainer() {
							if (!isCleanedUp) {
								isCleanedUp = true;
								container.remove({force:true, v:false}, function(errRemove, data) {
#if DockerDataToolsDebug
									traceCyan('getData removeContainer ${container.id} errRemove=$errRemove');
#end
									if (errRemove != null) {
										Log.error(errRemove);
										cleanupPromise.boundPromise.reject(errRemove);
									} else {
										cleanupPromise.resolve(true);
									}
								});
							}
							return cleanupPromise.boundPromise;
						}
						container.getArchive(getDataOpts, function(getErr, data) {
							if (getErr != null) {
								cleanupContainer()
									.then(function(_) {
										promise.boundPromise.reject(getErr);
									})
									.catchError(function(cleanupErr :Dynamic) {
										Log.error(cleanupErr);
										promise.boundPromise.reject({cleanupErr:cleanupErr, getErr:getErr});
									});
							} else {
								data.on(ReadableEvent.End, function() {
									cleanupContainer();
								});
								data.on(ReadableEvent.Error, function(err) {
									cleanupContainer();
								});
								promise.resolve({stream:data, disposed:cleanupPromise.boundPromise});
							}
						});
					}
				});
				return promise.boundPromise;
			});
	}

	public static function runImageGetStdOut(docker :Docker, image :String, command :Array<String>, volumes :Array<MountedDockerVolumeDef>) :Promise<String>
	{
		var promise = new DeferredPromise();
		var finalResult  = {end:promise.boundPromise};
		Assert.that(volumes[0].docker != null || volumes[0].dockerOpts != null);
		var docker = volumes[0].docker != null ? volumes[0].docker : new Docker(volumes[0].dockerOpts);
		var createOptions :CreateContainerOptions = {
			Image: image,
			HostConfig: {},
			Tty: false//needed for splitting stdout/err
		}

		createOptions.HostConfig.Binds = [];
		for (volume in volumes) {
			Assert.notNull(volume.name);
			Assert.notNull(volume.mount);
			createOptions.HostConfig.Binds.push('${volume.name}:${volume.mount}');
		}

		var stdout :String = '';
		var stderr :String = '';

		var stdoutStream = {
			write: function(s) {
				stdout += s;
			}
		};
		var stderrStream = {
			write: function(s) {
				stderr += s;
			}
		}

		DockerPromises.ensureImage(docker, createOptions.Image)
			.then(function(_) {


				docker.run(createOptions.Image, command, cast [stdoutStream, stderrStream], createOptions, {}, function(err, dataRun, container) {
					container.remove(function(errRemove, dataRemove) {
						if (promise != null) {
							if (err != null) {
								promise.boundPromise.reject(err);
							} else if (dataRun.StatusCode != 0) {
								promise.boundPromise.reject('Non-zero StatusCode data:$dataRun');
							} else {
								promise.resolve(stdout);
							}
							promise = null;
						}
					});
				});
			})
			.catchError(function(err) {
				if (promise != null) {
					promise.boundPromise.reject(err);
					promise = null;
				} else {
					Log.error({error:err});
				}
			});
		return promise.boundPromise;
	}

	inline static var EMPTY_DOCKER_IMAGE = 'tianon/true';
	inline static var VOLUME_MOUNT_POINT1 = '/_COPY_OP1';
	inline static var VOLUME_MOUNT_POINT2 = '/_COPY_OP2';
	inline static var DOCKER_IMAGE_DEFAULT = 'docker.io/busybox:latest';
}