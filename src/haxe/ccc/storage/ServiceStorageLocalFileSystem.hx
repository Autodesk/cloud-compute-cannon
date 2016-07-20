package ccc.storage;

import js.Error;
import js.node.Fs;
import js.node.Path;
import js.node.stream.Readable;
import js.node.stream.Writable;
import js.npm.FsExtended;
import js.npm.FsPromises;
import js.npm.TarGz;
import js.npm.TarFs;

import promhx.Promise;
import promhx.CallbackPromise;
import promhx.StreamPromises;
import promhx.deferred.DeferredPromise;

import ccc.storage.ServiceStorage;

using Lambda;
using StringTools;

class ServiceStorageLocalFileSystem
	extends ServiceStorageBase
{
	inline public static var STORAGE_LOCAL_DEFAULT_PATH = 'data/ServiceStorageLocalFileSystem/';

	public static function getService(?path :String) :ServiceStorageLocalFileSystem
	{
		path = path == null ? STORAGE_LOCAL_DEFAULT_PATH : path;
		return new ServiceStorageLocalFileSystem().setRootPath(path);
	}

	public function new()
	{
		super();
	}

	@post
	override public function postInjection()
	{
		super.postInjection();
		_rootPath = _rootPath == null ? STORAGE_LOCAL_DEFAULT_PATH : _rootPath;
	}

	override public function readFile(path :String) :Promise<IReadable>
	{
		Assert.notNull(path);
		path = getPath(path);
#if debug
		try {
			var stat = Fs.statSync(path);
			if (!stat.isFile()) {
				throw 'readFile but file missing $path';
			}
		} catch(err :js.support.Error) {
			var localPath = path;
			if (!path.startsWith('/')) {
				path = Path.join(js.Node.process.cwd(), path);
			}
			if (err.code == 'ENOENT') {
				var promise = new Promise();
				promise.reject('Missing file $localPath not found at $path');
				return promise;
			} else {
				var promise = new Promise();
				promise.reject(err);
				return promise;
			}
		}
#end
		//I'm casting here because we just pipe the stream to a writable stream.
		return Promise.promise(cast Fs.createReadStream(path));
	}

	override public function exists(path :String) :Promise<Bool>
	{
		Assert.notNull(path);
		path = getPath(path);
		try {
			var stat = Fs.statSync(path);
			return Promise.promise(stat.isFile());
		} catch(err :js.support.Error) {
			if (err.code == 'ENOENT') {
				return Promise.promise(false);
			} else {
				throw 'exists but Fs.statSync($path) threw $err';
			}
		}
	}

	override public function readDir(?path :String) :Promise<IReadable>
	{
		path = getPath(path);
		return Promise.promise(TarFs.pack(path));
	}

	override public function writeFile(path :String, data :IReadable) :Promise<Bool>
	{
		Assert.notNull(path);
		Assert.notNull(data);
		path = getPath(path);
		if (!path.startsWith('/')) {
			path = js.Node.process.cwd() + '/' + path;
		}

		var alreadyExists = FsExtended.existsSync(path);

		return Promise.promise(true)
			.pipe(function(_) {
				var dir = Path.dirname(path);
				if (dir != null) {
					js.node.ChildProcess.execSync('mkdir -p "$dir"', {stdio:['ignore','pipe', untyped js.Node.process.stderr]});
					return Promise.promise(true);
				} else {
					return Promise.promise(true);
				}
			})
#if (tests || debug)
			.then(function(_) {
				var dir = Path.dirname(path);
				try {
					var stat = Fs.statSync(dir);
					if (!stat.isDirectory()) {
						throw 'Failed to create dir=$dir stat=$stat';
					}
				} catch(err :js.support.Error) {
					throw 'Failed to create dir=$dir err=$err';
				}
				return true;
			})
#end
			.pipe(function(_) {
				//Listen to the FINISH event of the writable stream
				//NOT the 'end' or 'close' event of the readable stream
				//http://stackoverflow.com/questions/13156243/event-associated-with-fs-createwritestream-in-node-js
				return StreamPromises.pipe(data, Fs.createWriteStream(path), [WritableEvent.Finish], 'ServiceStorageLocalFileSystem.path(stream, $path)');
			});
	}

	override public function getFileWritable(path :String) :Promise<IWritable>
	{
		path = getPath(path);
		return Promise.promise(true)
			.pipe(function(_) {
				var dir = Path.dirname(path);
				if (dir != null) {
					return FsPromises.mkdir(dir);
				} else {
					return Promise.promise(true);
				}
			})
			.then(function(_) {
				return cast Fs.createWriteStream(path);
			});
	}

	override public function copyFile(source :String, target :String) :Promise<Bool>
	{
		Assert.notNull(source);
		Assert.notNull(target);
		source = getPath(source);
		target = getPath(target);
		var promise = new CallbackPromise();
		FsExtended.copyFile(source, target, promise.cb1);
		return promise.then(function(_) return true);
	}

	override public function deleteFile(path :String) :Promise<Bool>
	{
		Assert.notNull(path);
		path = getPath(path);
		FsExtended.deleteFileSync(path);
		return Promise.promise(true);
	}

	override public function deleteDir(?path :String) :Promise<Bool>
	{
		path = getPath(path);
		FsExtended.deleteDirSync(path);
		return Promise.promise(true);
	}

	override public function listDir(?path :String) :Promise<Array<String>>
	{
		path = getPath(path);
		var promise = new DeferredPromise();
		FsExtended.listAll(path,
			{
				recursive: true,
				filter: function(itemPath, stat) {
					return stat.isFile();
				}
			},
			function(?err, files) {
				if (err != null) {
					promise.boundPromise.reject(err);
				} else {
					promise.resolve(files != null ? files : []);
				}
			});
		return promise.boundPromise;
	}

	override public function makeDir(?path :String) :Promise<Bool>
	{
		var path1 = path;
		path = getPath(path);
		FsExtended.ensureDirSync(path);
		return Promise.promise(true);
	}

	override public function setRootPath(val :String)
	{
		super.setRootPath(val);
		//This breaks the clean package separation maintained until now.
		//But it's only used testing.
		if (!ccc.compute.ConnectionToolsDocker.isInsideContainer()) {
			_rootPath = js.node.Path.resolve(_rootPath);
		}
		_rootPath = ensureEndsWithSlash(_rootPath);
		return this;
	}

	override public function appendToRootPath(path :String) :ServiceStorage
	{
		return getService(getPath(path));
	}

	override public function toString()
	{
		return '[StorageLocal _rootPath=$_rootPath]';
	}
}