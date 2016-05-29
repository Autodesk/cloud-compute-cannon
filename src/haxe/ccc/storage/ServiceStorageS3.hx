package ccc.storage;

import js.node.stream.Readable;
import js.node.stream.Writable;

import js.npm.PkgCloud;

import promhx.Promise;
import promhx.StreamPromises;
import promhx.deferred.DeferredPromise;

import ccc.compute.Definitions;
import ccc.storage.ServiceStorageBase;
import ccc.storage.StorageSourceType;
import ccc.storage.StorageDefinition;

using StringTools;
using Lambda;

class ServiceStorageS3 extends ServiceStorageBase
{
	private var _defaultContainerName :String = "bionano-platform-test"; // we always need a bucket

	private static var precedingSlash = ~/^\/+/;
	private static var endingSlash = ~/\/+$/;
	private static var extraSlash = ~/\/{2,}/g;

	private static var splitRegEx = ~/\/+/g;
	private static var replaceChar :String = "--";

	public function new()
	{
		super();
	}

	private function getClient() :StorageClientP
	{
		return _config.storageClient;
	}

	public function getContainerName(?options: Dynamic) :String {
		if (options != null && options.container != null) {
			return options.container;
		}

		return _defaultContainerName;
	}

	override public function setConfig(config :StorageDefinition) :ServiceStorageBase
	{
		if (config.defaultContainer != null) {
			_defaultContainerName = config.defaultContainer;
		}

		return super.setConfig(config);
	}

	public function convertPath(?path: String) :String
	{
		path = ((path != null) ? path : '');
		path = (_rootPath + path);

		// strip preceding slash
		var result = precedingSlash.replace(path, '');

		// AWS S3 allows path-like object names so this functionality isn't necessary
		// convert a path to a container replacing / with -
//		result = splitRegEx.replace(result, replaceChar);

		return result;
	}

	override public function readFile(path :String) :Promise<IReadable>
	{
		var client = this.getClient();
		var options :Dynamic = {
			container: this.getContainerName(),
			remote: convertPath(path)
		};

		try {
			var readStream = client.download(options);

			readStream.on('error', function(err) {
				Log.error('ERROR (THIS IS OUT OF THE PROMISE CHAIN) ServiceStorageS3.readFile path=$path err=$err');
			});

			return Promise.promise(readStream);
		} catch(err :Dynamic) {
			return Promise.promise(true)
				.then(function(_) {
					throw err;
					return null;
				});
		}
	}

	override public function readDir(?path :String) :Promise<IReadable>
	{
		throw 'Not implemented';
		return null;
	}

	override public function writeFile(path :String, data :IReadable) :Promise<Bool>
	{
		return this.getFileWritable(path)
			.pipe(function(writeStream) {
				return StreamPromises.pipe(data, writeStream, [WritableEvent.Finish], 'ServiceStorageS3.writeFile path=$path');
			});
	}

	override public function getFileWritable(path :String) :Promise<IWritable>
	{
		var client = this.getClient();
		var options :Dynamic = {
			container: this.getContainerName(),
			remote: convertPath(path)
		};
		try {
			var writeStream = client.upload(options);

			writeStream.on(WritableEvent.Error, function(err) {
				Log.error('ERROR (THIS IS OUT OF THE PROMISE CHAIN) writing file path=$path err=$err');
			});
			var isFinished = false;
			writeStream.once(WritableEvent.Finish, function() {
				isFinished = true;
			});
			writeStream.on('success', function(file) {
				js.Node.setImmediate(function() {
					if (!isFinished) {
						writeStream.emit(WritableEvent.Finish, writeStream);
					}
				});
			});

			return Promise.promise(writeStream);
		}  catch(err :Dynamic) {
			return Promise.promise(true)
				.then(function(_) {
					throw err;
					return null;
				});
		}
	}

	override public function copyFile(source :String, target :String) :Promise<Bool>
	{
		Assert.notNull(source);
		Assert.notNull(target);

		return Promise.promise(true)
			.pipe(function (_) {
				return this.readFile(source);
			})
			.pipe(function(readStream) {
				return this.writeFile(target, readStream);
			});
	}

	override public function deleteFile(path :String) :Promise<Bool>
	{
		Assert.notNull(path);

		var client = this.getClient();
		return client.getContainer(this.getContainerName())
			.pipe(function(container) {
				return client.getFiles(container)
					.then(function(files) {
						return {
							container: container,
							files: files
						};
					});
			})
			.pipe(function(inputs) {
				var files = inputs.files;
				var file :File = files.find(function (File) {
					return File.name == path;
				});

				if (file == null) {
					return Promise.promise(false);
				}

				return client.removeFile(inputs.container, file);
			});
	}

	override public function deleteDir(?path :String) :Promise<Bool>
	{
		if (path == null) {
			Log.error('deleteDir called with no path; ServiceStorageS3 does nothing in this case.');
			return Promise.promise(true);
		}

		var client = this.getClient();

		return client.getContainer(this.getContainerName())
			.pipe(function (container) {
				return client.getFiles(container)
				.then(function (files) {
					return {
						container: container,
						files: files
					}
				});
			})
			.then(function (inputs) {
				var promises = [];
				inputs.files.iter(function (file :File) {
					promises.push(client.removeFile(inputs.container, file));
				});
				return promises;
			})
			.pipe(function (promises) {
				return Promise.whenAll(promises);
			})
			.then(function (_) {
				return true;
			});
	}

	override public function listDir(?path :String) :Promise<Array<String>>
	{
		var client = this.getClient();
		return client.getContainer(this.getContainerName())
			.pipe(function(container) {
				return client.getFiles(container);
			})
			.then(function(files :Array<File>) {
				return files.map(function (File) {
					if ((path != null) && (File.name.startsWith(path))){
						return File.name;
					}

					return File.name;
				});
			});
	}

	override public function makeDir(?path :String) :Promise<Bool>
	{
		// AWS doesn't require explit creation of directories as it just stores directories in object names
		return Promise.promise(true);
	}

	override public function setRootPath(path :String) :ServiceStorage
	{
		if (! endingSlash.match(path)) {
			path = path + '/';
		}

		_rootPath = extraSlash.replace(path, '/');
		return this;
	}

	override public function getRootPath() :String
	{
		return _rootPath;
	}

	override public function appendToRootPath(path :String) :ServiceStorage
	{
		if (! endingSlash.match(path)) {
			path = path + '/';
		}
		_rootPath = extraSlash.replace(_rootPath + path, '/');
		return this;
	}

	override public function getPath(p :String) :String
	{
		if (p != null && p.startsWith('/')) {
			return precedingSlash.replace(p, '');
		} else {
			return convertPath(p);
		}
	}

	override public function getExternalUrl(?path :String) :String
	{
		var baseUrl = _config.httpAccessUrl;
		var bucket = _defaultContainerName;
		var url = baseUrl + '/' + bucket + this.getRootPath();
		if (!url.endsWith('/')) {
			url = url + '/';
		}
		if (path != null) {
			url = url + path;
		}
		return url;
	}

	// stronger assertions than StorageTools.getConfigFromServiceConfiguration
	public static function getS3ConfigFromServiceConfiguration(input :ServiceConfiguration) :StorageDefinition
	{
		Assert.notNull(input.server);

		var storageConfig = input.server.storage;
		Assert.notNull(storageConfig);
		Assert.notNull(storageConfig.type);
		Assert.notNull(storageConfig.rootPath);
		Assert.notNull(storageConfig.defaultContainer);
		Assert.notNull(storageConfig.httpAccessUrl);
		Assert.notNull(storageConfig.credentials);

		return {
			type: cast storageConfig.type,
			storageClient: PkgCloud.storage.createClient(storageConfig.credentials),
			rootPath: storageConfig.rootPath,
			defaultContainer: storageConfig.defaultContainer,
			httpAccessUrl: storageConfig.httpAccessUrl
		};
	}
}