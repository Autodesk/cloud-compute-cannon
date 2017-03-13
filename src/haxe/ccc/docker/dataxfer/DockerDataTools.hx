package ccc.docker.dataxfer;

/**
 * -D DockerDataToolsDebug for extra logging
 */
import haxe.DynamicAccess;
import haxe.Json;

import js.Node;
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
import promhx.PromiseTools;

import util.streams.StreamTools;
import util.DockerTools;
import util.TarTools;

import t9.util.ColorTraces.*;

using Lambda;
using StringTools;

enum DataTransferType {
	S3;
	Rsync;
	Sftp;
	Local;
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
				return stdout != null ? stdout.trim().split('\n').map(function(s) return s.substr(VOLUME_MOUNT_POINT1.length + 1)).filter(function(s) return s.length > 0): [];
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

	public static function transferVolumeToFiles(volume :MountedDockerVolumeDef) :Promise<DynamicAccess<String>>
	{
		Assert.notNull(volume);
		return getDataFiles(volume)
			.then(function(blob) {
				return blob.files;
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

	public static function transferFilesToVolume(files :DynamicAccess<String>, volume :MountedDockerVolumeDef) :Promise<Bool>
	{
		Assert.notNull(volume);
		Assert.notNull(files);
		var readableTarStream = TarTools.createTarStreamFromStrings(files);
		return addData(volume, readableTarStream, volume.path)
			.then(function(_) return true);
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
				var command = ['aws', 's3', 'cp', sourceUri, targetUri, '--recursive'].concat(copyCommand);
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
					command: ['aws', 's3', 'cp', sourceUri, targetUri, '--recursive'],
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
		return DockerTools.runDockerCommand(docker, AWS_CLI_IMAGE, command, env)
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

		return DockerTools.runDockerCommand(docker, AWS_CLI_IMAGE, command, env, volumes, outStream, errStream);
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


		return {end:DockerTools.runDockerCommand(docker, op.command.image, op.command.command, op.command.env, volumes, outStream, errStream)};
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

	/**
	 * Pull files from the data container linked to the data volume into
	 * an object
	 * @param  volume        :DockerVolumeDef [description]
	 * @param  ?subDirectory :String          [description]
	 * @return               [description]
	 */
	public static function getDataFiles(volume :DockerVolumeDef, ?subDirectory :String) :Promise<{files:DynamicAccess<String>, disposed:Promise<Bool>}>
	{
		return getData(volume, subDirectory)
			.pipe(function(streamAndDisposed) {
				var promise = new DeferredPromise();
				var tarStream = streamAndDisposed.stream;
				var extract = TarStream.extract();
				var files :DynamicAccess<String> = {};
				extract.on(TarExtractEvent.Entry, function(header, stream, next) {
					// header is the tar header
					// stream is the content body (might be an empty stream)
					// call next when you are done with this entry
					StreamPromises.streamToString(stream)
						.then(function(s) {
							var name = header.name;
							name = name.startsWith('./') ? name.substr(2) : name;
							name = name.trim();
							if (name.length > 0) {
								files.set(name, s);
							}
							next(); // ready for next entry
						})
						.catchError(function(err) {
							promise.boundPromise.reject(err);
						});
				});

				extract.on(TarExtractEvent.Finish, function() {
					promise.resolve({files:files, disposed:streamAndDisposed.disposed});
				});

				tarStream.pipe(extract);

				return promise.boundPromise;
			});
	}

	public static function getDataFilesFromContainer(container :DockerContainer, path :String) :Promise<DynamicAccess<String>>
	{
		var promise = new DeferredPromise();

		var getDataOpts = {
			path: path,
		}

		container.getArchive(getDataOpts, function(err, data) {
			if (err != null) {
				promise.boundPromise.reject(err);
			} else {
				var extract = TarStream.extract();
				var files :DynamicAccess<String> = {};
				extract.on(TarExtractEvent.Entry, function(header, stream, next) {
					// header is the tar header
					// stream is the content body (might be an empty stream)
					// call next when you are done with this entry
					StreamPromises.streamToString(stream)
						.then(function(s) {
							var name = header.name;
							name = name.startsWith(path.substr(1)) ? name.substr(path.length) : name;
							name = name.startsWith('./') ? name.substr(2) : name;
							name = name.trim();
							if (name.length > 0) {
								files.set(name, s);
							}
							next(); // ready for next entry
						})
						.catchError(function(err) {
							promise.boundPromise.reject(err);
						});
				});

				extract.on(TarExtractEvent.Finish, function() {
					promise.resolve(files);
				});

				data.pipe(extract);
			}
		});

		return promise.boundPromise;
	}

	public static function putDataFilesInContainer(container :DockerContainer, path :String, files :DynamicAccess<String>) :Promise<Bool>
	{
		var promise = new DeferredPromise();

		var putDataOpts = {
			path: path,
			noOverwriteDirNonDir: 'true'
		}

		var tarStream = TarStream.pack();
		for (fileName in files.keys()) {
			tarStream.entry({name: fileName}, files.get(fileName));
		}
		tarStream.finalize();

		container.putArchive(tarStream, putDataOpts, function(err, data) {
			if (err != null) {
				promise.boundPromise.reject(err);
			} else {
				promise.resolve(true);
			}
		});

		return promise.boundPromise;
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