package ccc.storage;

import js.node.stream.Readable;
import js.node.stream.Writable;

import js.npm.PkgCloud;

import promhx.Promise;
import promhx.PromiseTools;
import promhx.StreamPromises;
import promhx.deferred.DeferredPromise;

import ccc.compute.shared.Definitions;
import ccc.storage.ServiceStorageBase;
import ccc.storage.StorageSourceType;
import ccc.storage.StorageDefinition;

using Lambda;
using StringTools;

class ServiceStoragePkgCloud extends ServiceStorageBase
{
	var _containerName :String = "bionano-platform-test"; // we always need a bucket
	var _client :StorageClientP;
	var _httpAccessUrl :String;

	private static var precedingSlash = ~/^\/+/;
	private static var endingSlash = ~/\/+$/;
	private static var extraSlash = ~/\/{2,}/g;
	private static var splitRegEx = ~/\/+/g;
	private static var replaceChar :String = "--";

	public function new()
	{
		super();
	}

	override public function toString()
	{
		return '[StoragePkgCloud _rootPath=$_rootPath container=${_containerName} externalUrlPrefix=${_httpAccessUrl}]';
	}

	private function getClient() :StorageClientP
	{
		return _client;
	}

	public function getContainerName(?options: Dynamic) :String
	{
		return _containerName;
	}

	override public function setConfig(config :StorageDefinition) :ServiceStorageBase
	{
		Assert.notNull(config.container);
		Assert.notNull(config.httpAccessUrl);
		Assert.notNull(config.credentials);

		if (config.container != null) {
			_containerName = config.container;
		}

		_httpAccessUrl = ensureEndsWithSlash(config.httpAccessUrl);
		// _client = PkgCloud.storage.createClient(config.credentials);

		return super.setConfig(config);
	}

	override public function clone() :ServiceStorage
	{
		var copy = new ServiceStorageS3();
		var config = Reflect.copy(_config);
		config.httpAccessUrl = _httpAccessUrl;
		config.container = _containerName;
		config.rootPath = _rootPath;
		copy.setConfig(config);
		return copy;
	}

	override public function exists(path :String) :Promise<Bool>
	{
		path = getPath(path);
		var client = getClient();
		return client.getContainer(getContainerName())
			.pipe(function(container) {
				return client.getFile(container, path)
					.then(function(file) {
						return true;
					})
					.errorPipe(function(err) {
						return Promise.promise(false);
					});
			});
	}

	override public function readFile(path :String) :Promise<IReadable>
	{
		path = getPath(path);
		var client = this.getClient();
		var options :Dynamic = {
			container: this.getContainerName(),
			remote: path
		};
		try {
			var readStream = client.download(options);
			readStream.on('error', function(err) {
				Log.error('ERROR (THIS IS OUT OF THE PROMISE CHAIN) ServiceStorageS3.readFile path=$path err=$err');
			});
			return Promise.promise(readStream);
		} catch(err :Dynamic) {
			return PromiseTools.error(err);
		}
	}

	override public function readDir(?path :String) :Promise<IReadable>
	{
		throw 'readDir(...) Not implemented';
		return null;
	}

	override public function writeFile(path :String, data :IReadable) :Promise<Bool>
	{
		path = getPath(path);
		return getFileWritableInternal(path)
			.pipe(function(writeStream) {
				return StreamPromises.pipe(data, writeStream, ['success'], 'ServiceStorageS3.writeFile path=$path');
			});
	}

	// override public function getFileWritable(path :String) :Promise<IWritable>
	// {
	// 	path = getPath(path);
	// 	return getFileWritableInternal(path);
	// }

	function getFileWritableInternal(path :String) :Promise<IWritable>
	{
		var client = getClient();
		var options :Dynamic = {
			container: getContainerName(),
			remote: path
		};
		try {
			var writeStream = client.upload(options);
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
		path = getPath(path);

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
		path = getPath(path);
		if (path != null && path.length == 0) {
			path = null;
		}
		//S3/AWS only
		path = ensureEndsWithSlash(path);
		var client = this.getClient();
		return client.getContainer(this.getContainerName())
			.pipe(function(container) {
				var options = {prefix:path};
				return client.getFiles(container, options);
			})
			.then(function(files :Array<File>) {
				return files.map(function (f) {
					if (path != null) {
						return f.name.substr(path.length);
					} else {
						return f.name;
					}
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
		super.setRootPath(path);
		_rootPath = removePrecedingSlash(_rootPath);
		return this;
	}

	override public function appendToRootPath(path :String) :ServiceStorage
	{
		var copy = clone();
		path = path.replace('//', '/');
		copy.setRootPath(getPath(path));
		return copy;
	}

	override public function getPath(p :String) :String
	{
		if (p != null && _httpAccessUrl != null && p.startsWith(_httpAccessUrl)) {
			p = p.substr(_httpAccessUrl.length);
		}
		var path = super.getPath(p);
		return removePrecedingSlash(path);
// 		// AWS S3 allows path-like object names so this functionality isn't necessary
// 		// convert a path to a container replacing / with -
//		result = splitRegEx.replace(result, replaceChar);
// 		return result;
	}

	override public function getExternalUrl(?path :String) :String
	{
		path = getPath(path);
		if (_httpAccessUrl != null) {
			return _httpAccessUrl + path;
		} else {
			return path;
		}
	}

	static function removePrecedingSlash(s :String) :String
	{
		if (s.startsWith('/')) {
			return removePrecedingSlash(s.substring(1));
		} else {
			return s;
		}
	}
}