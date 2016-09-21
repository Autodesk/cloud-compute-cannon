package ccc.docker.dataxfer;

import ccc.compute.ConnectionToolsDocker;
import ccc.docker.dataxfer.DockerDataTools;
import ccc.storage.ServiceStorageS3;
import ccc.storage.StorageSourceType;

import haxe.DynamicAccess;
import haxe.unit.async.PromiseTest;

import js.node.Path;
import js.node.Fs;
import js.node.Buffer;
import js.node.stream.Readable;
import js.npm.docker.Docker;
import js.npm.shortid.ShortId;
import js.npm.tarstream.TarStream;
import js.npm.fsextended.FsExtended;

import promhx.Promise;
import promhx.deferred.DeferredPromise;
import promhx.StreamPromises;

import util.streams.StreamTools;

using promhx.DockerPromises;
using promhx.PromiseTools;

class TestDataTransfer extends PromiseTest
{
	@timeout(10000)
	public function testVolumeLs() :Promise<Bool>
	{
		var testObj = createTestDataVolumeAndCheckFunction();
		var source = testObj.source;
		var tarStream = testObj.tarStream;
		var files = testObj.files;

		return DockerDataTools.createVolumeWithData(source, tarStream)
			.pipe(function(_) {
				return DockerDataTools.lsVolume(source)
					.then(function(lsFiles) {
						assertEquals(lsFiles.length, files.keys().length);
						for (key in files.keys()) {
							assertTrue(lsFiles.has(key));
						}
						return true;
					});
			});
	}

	@timeout(10000)
	public function testDataInAndOutOfVolume() :Promise<Bool>
	{
		var testObj = createTestDataVolumeAndCheckFunction();
		var source = testObj.source;
		var tarStream = testObj.tarStream;

		return DockerDataTools.createVolumeWithData(source, tarStream)
			.pipe(function(_) {
				return testObj.check(source);
			});
	}

	@timeout(10000)
	public function testVolumeToLocalDisk() :Promise<Bool>
	{
		var subfolder = 'someDir3';
		var docker = new Docker(ConnectionToolsDocker.getDockerConfig());
		var testObj = createTestDataVolumeAndCheckFunction();
		var source = testObj.source;
		var tarStream = testObj.tarStream;
		var testFiles = testObj.files.keys()
			.filter(function(path) return path.startsWith(subfolder))
			.map(function(path) return path.replace(subfolder, ''))
			.map(function(path) return path.substr(1));

		return DockerDataTools.createVolumeWithData(source, tarStream)
			.pipe(function(_) {
				//Transfer to disk
				var baseFolder = Path.join(TEMP_FOLDER, ShortId.generate());
				FsExtended.ensureDirSync(baseFolder);
				var sourceCopy = Reflect.copy(source);
				sourceCopy.path = subfolder;
				return DockerDataTools.transferVolumeToDisk(sourceCopy, baseFolder)
					.then(function(_) {
						//Ok sorry, I'm not checking the content of these files,
						var localFiles = FsExtended.listAllSync(baseFolder, {recursive:true, filter:function(path, stat) return stat.isFile()});
						assertEquals(localFiles.length, testFiles.length);
						for (i in 0...localFiles.length) {
							assertEquals(localFiles[i], testFiles[i]);
						}
						return true;
					});
			});
	}

	@timeout(10000)
	public function testLocalDiskInAndOutOfLocalVolume() :Promise<Bool>
	{
		var docker = new Docker(ConnectionToolsDocker.getDockerConfig());
		var testObj = createTestDataVolumeAndCheckFunction();
		var source = testObj.source;
		var tarStream = testObj.tarStream;

		return DockerDataTools.createVolumeWithData(source, tarStream)
			.pipe(function(_) {
				//Transfer to disk
				var baseFolder = Path.join(TEMP_FOLDER, ShortId.generate());
				FsExtended.ensureDirSync(baseFolder);
				return DockerDataTools.transferLocalVolumeToLocalDisk(source, baseFolder).end
					.pipe(function(_) {
						var source2 :MountedDockerVolumeDef = {
							docker: docker,
							name: 'testVolumeKillMe_${ShortId.generate()}'
						};
						return DockerDataTools.createVolume(source2)
							.pipe(function(_) {
								_volumesCreated.push(docker.getVolume(source2.name));
								return DockerDataTools.transferLocalDiskToLocalVolume(baseFolder, source2).end;
							})
							.pipe(function(_) {
								return testObj.check(source2);
							});
					});
			});
	}

	/**
	 * Make sure subdirectory paths are respected
	 */
	@timeout(10000)
	public function testVolumeSubDirToVolumeSubDir() :Promise<Bool>
	{
		var docker = new Docker(ConnectionToolsDocker.getDockerConfig());
		var parentDir = 'foobar/blarg/';
		var testObj = createTestDataVolumeAndCheckFunction();
		var source = testObj.source;
		var tarStream = testObj.tarStream;

		return DockerDataTools.createVolumeWithData(source, tarStream)
			.pipe(function(_) {
				var source2 :MountedDockerVolumeDef = {
					dockerOpts: ConnectionToolsDocker.getDockerConfig(),
					name: 'testVolumeKillMe_${ShortId.generate()}'
				};

				return DockerDataTools.createVolume(source2)
					.pipe(function(_) {
						_volumesCreated.push(docker.getVolume(source2.name));
						return DockerDataTools.getData(source);
					})
					.pipe(function(result) {
						return DockerDataTools.addData(source2, result.stream, parentDir)
							.pipe(function(_) {
								return result.disposed;
							});
					})
					.pipe(function(_) {
						return testObj.check(source2, parentDir);
					});
			});
	}

	@timeout(30000)
	public function testVolumeToS3() :Promise<Bool>
	{
		var docker = new Docker(ConnectionToolsDocker.getDockerConfig());
		var awsKey = Sys.environment()['AWS_S3_KEY'];
		var awsKeyId = Sys.environment()['AWS_S3_KEYID'];
		var S3Bucket = Sys.environment()['AWS_S3_BUCKET'];
		if (awsKey == null || awsKeyId == null || S3Bucket == null) {
			traceYellow('Cannot run ${}.testVolumeToS3 without S3 credentials (AWS_S3_KEY and AWS_S3_KEYID and AWS_S3_BUCKET as env vars)');
			return Promise.promise(true);
		}

		var testObj = createTestDataVolumeAndCheckFunction();
		var source = testObj.source;
		var tarStream = testObj.tarStream;

		return DockerDataTools.createVolumeWithData(source, tarStream)
			.pipe(function(_) {
				//get the data and check it against the inputs
				var target = {
					keyId: awsKeyId,
					key: awsKey,
					bucket: S3Bucket,
					path: '/tests/testVolumeToS3/${ShortId.generate()}'
				}
				return DockerDataTools.transferVolumeToS3(source, target).end
					.pipe(function(_) {
						//Copy S3 to a different container
						var sourceDocker = ConnectionToolsDocker.getDockerConfig();
						var fromS3 :MountedDockerVolumeDef = {
							dockerOpts: sourceDocker,
							name: 'testVolumeKillMe_${ShortId.generate()}'
						};
						return DockerDataTools.createVolume(fromS3)
							.pipe(function(_) {
								_volumesCreated.push(docker.getVolume(fromS3.name));
								return DockerDataTools.transferS3ToVolume(target, fromS3).end
									.pipe(function(_) {
										return testObj.check(fromS3);
									});
								});
					});
			});
	}

	@timeout(30000)
	public function testS3ToVolume() :Promise<Bool>
	{
		var docker = new Docker(ConnectionToolsDocker.getDockerConfig());
		var awsKey = Sys.environment()['AWS_S3_KEY'];
		var awsKeyId = Sys.environment()['AWS_S3_KEYID'];
		var S3Bucket = Sys.environment()['AWS_S3_BUCKET'];

		if (awsKey == null || awsKeyId == null || S3Bucket == null) {
			traceYellow('Cannot run ${}.testS3ToVolume without S3 credentials (AWS_S3_KEY and AWS_S3_KEYID and S3Bucket as env vars)');
			return Promise.promise(true);
		}

		function randInt() {
			return Std.int(Math.random() * 255);
		}
		var fileData :DynamicAccess<Dynamic> = {};
		fileData['someDir1/file1_${ShortId.generate()}'] = 'somestring${ShortId.generate()}';
		fileData['someDir2/file2_${ShortId.generate()}'] = new Buffer([randInt(), randInt(), randInt()]);
		fileData['someDir3/someDir4/file3_${ShortId.generate()}'] = 'somestring${ShortId.generate()}';
		fileData['someDir3/someDir5/someDir6/file4_${ShortId.generate()}'] = 'somestring${ShortId.generate()}';

		var rootPath = '/tests/testS3ToVolume/${ShortId.generate()}/';
		var s3Storage = new ServiceStorageS3().setConfig({
			type: StorageSourceType.S3,
			rootPath: rootPath,
			container: S3Bucket,
			credentials: {
				accessKeyId: awsKeyId,
				secretAccessKey: awsKey
			}
		});

		var promises = fileData.keys().map(function(key) {
			var stream = if (Buffer.isBuffer(fileData[key])) {
				StreamTools.bufferToStream(fileData[key]);
			} else {
				StreamTools.stringToStream(fileData[key]);
			}
			return s3Storage.writeFile(key, stream);
		});

		return Promise.whenAll(promises)
			.pipe(function(_) {
				var source = {
					keyId: awsKeyId,
					key: awsKey,
					bucket: S3Bucket,
					path: rootPath
				}
				var targetVolume :MountedDockerVolumeDef = {
					docker: docker,
					name: 'testVolumeKillMe_${ShortId.generate()}'
				};
				_volumesCreated.push(docker.getVolume(targetVolume.name));
				return DockerDataTools.createVolume(targetVolume)
					.pipe(function(_) {
						return DockerDataTools.transferS3ToVolume(source, targetVolume).end
							.pipe(function(_) {
								//get the data and check it against the inputs
								return DockerDataTools.getData(targetVolume)
									.pipe(function(obj) {
										var stream = obj.stream;
										var tarstream = TarStream.extract();
										var promise = new DeferredPromise();
										var copiedFileData :DynamicAccess<Buffer> = {};
										tarstream.on(TarExtractEvent.Entry, function(header, stream, cb) {

											if (header.type == TarPackEntryType.file) {
												var name = header.name;
												if (name.startsWith('./')) {
													name = name.substr(2);
												}
												StreamPromises.streamToBuffer(stream)
													.then(function(buffer) {
														copiedFileData[name] = buffer;
														cb();
													})
													.catchError(function(err) {
														Log.error({message:'Failed to untar', header:header, error:err});
														if (promise != null) {
															promise.boundPromise.reject(err);
															promise = null;
														}
														cb();
													});
											} else {
												cb();
											}
											stream.on(ReadableEvent.End, function() {
												//Don't need this because the streamToBuffer conversion will
												//get the 'end' event
											});
										});
										tarstream.on(TarExtractEvent.Finish, function() {
											var fileDataKeys = fileData.keys();
											for (key in fileDataKeys) {
												var targetKey = key;
												if (Buffer.isBuffer(fileData[key])) {
													assertTrue(fileData[key].equals(copiedFileData[targetKey]));
												} else {
													assertEquals(fileData[key], copiedFileData[targetKey]);
												}
											}

											if (promise != null) {
												promise.resolve(true);
												promise = null;
											}
										});
										stream.pipe(tarstream);
										return promise.boundPromise
											.pipe(function(result) {
												return obj.disposed
													.then(function(_) {
														return result;
													});
											});
									});
							});
					})
					.thenTrue();
			});
	}

	function createTestDataVolumeAndCheckFunction()
	{
		return createTestDataVolumeAndCheckFunctionStatic(this);
	}

	static function createTestDataVolumeAndCheckFunctionStatic(testRunner :PromiseTest)
	{
		var sourceDocker = ConnectionToolsDocker.getDockerConfig();
		var source :MountedDockerVolumeDef = {
			dockerOpts: sourceDocker,
			name: 'testVolumeKillMe_${ShortId.generate()}'
		};

		function randInt() {
			return Std.int(Math.random() * 255);
		}
		var fileData :DynamicAccess<Dynamic> = {};
		fileData['someDir1/file1_${ShortId.generate()}'] = 'somestring${ShortId.generate()}';
		fileData['someDir2/file2_${ShortId.generate()}'] = new Buffer([randInt(), randInt(), randInt()]);
		fileData['someDir3/someDir4/file3_${ShortId.generate()}'] = 'somestring${ShortId.generate()}';
		fileData['someDir3/someDir5/someDir6/file4_${ShortId.generate()}'] = 'somestring${ShortId.generate()}';

		var docker = new Docker(sourceDocker);

		var tarStream = TarStream.pack();
		for (name in fileData.keys()) {
			tarStream.entry({name:name}, fileData[name]);
		}
		tarStream.finalize();

		//Add the created volume to the clean up list
		_volumesCreated.push(docker.getVolume(source.name));

		var check = function(sourceDockerDef, ?parentDirPrefix :String = null, ?extractVolumePath :String) {
			//get the data and check it against the inputs
			return DockerDataTools.getData(sourceDockerDef)
				.pipe(function(obj) {
					var stream = obj.stream;
					var tarstream = TarStream.extract();
					var promise = new DeferredPromise();
					var copiedFileData :DynamicAccess<Buffer> = {};
					tarstream.on(TarExtractEvent.Entry, function(header, stream, cb) {

						if (header.type == TarPackEntryType.file) {
							var name = header.name;
							if (name.startsWith('./')) {
								name = name.substr(2);
							}
							StreamPromises.streamToBuffer(stream)
								.then(function(buffer) {
									copiedFileData[name] = buffer;
									cb();
								})
								.catchError(function(err) {
									Log.error({message:'Failed to untar', header:header, error:err});
									if (promise != null) {
										promise.boundPromise.reject(err);
										promise = null;
									}
									cb();
								});
						} else {
							cb();
						}
						stream.on(ReadableEvent.End, function() {
							//Don't need this because the streamToBuffer conversion will
							//get the 'end' event
						});
					});
					tarstream.on(TarExtractEvent.Finish, function() {
						var fileDataKeys = extractVolumePath == null ? fileData.keys() : fileData.keys().filter(function(path) return path.startsWith(extractVolumePath));
						for (key in fileDataKeys) {
							var targetKey = (parentDirPrefix != null ? parentDirPrefix : '') + key;
							if (extractVolumePath != null) {
								targetKey = extractVolumePath.replace(extractVolumePath, '');
							}
							if (Buffer.isBuffer(fileData[key])) {
								testRunner.assertTrue(fileData[key].equals(copiedFileData[targetKey]));
							} else {
								testRunner.assertEquals(fileData[key], copiedFileData[targetKey]);
							}
						}

						if (promise != null) {
							promise.resolve(true);
							promise = null;
						}
					});
					stream.pipe(tarstream);
					return promise.boundPromise
						.pipe(function(result) {
							return obj.disposed
								.then(function(_) {
									return result;
								});
						});
				});
		}

		return {
			tarStream: tarStream,
			source: source,
			check: check,
			files: fileData
		}
	}

	static var _volumesCreated :Array<DockerVolume> = [];
	var _sourceVolumeName :String;
	var _sourceVolumeFiles :Map<String, Buffer>;

	public function new() {}

	override public function setup() :Promise<Bool>
	{
		FsExtended.deleteDirSync(TEMP_FOLDER);
		return null;
		//Create a volume and write some data
	}

	override public function tearDown() :Promise<Bool>
	{
		FsExtended.deleteDirSync(TEMP_FOLDER);
		return Promise.whenAll(_volumesCreated.map(function(v) {
#if DockerDataToolsDebug
			traceCyan('removeVolume ${v.name}');
#end
			return DockerPromises.removeVolume(v)
				.errorPipe(function(err) {
					Log.error(err);
					return Promise.promise(true);
				});
		}))
		.then(function(_) {
			_volumesCreated = [];
			return true;
		});
	}

	static var TEMP_FOLDER = './testDataTransfer/';
}