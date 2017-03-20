package ccc.storage;

import ccc.storage.ServiceStorage;
import ccc.storage.StorageTools;

import js.node.Path;
import js.node.stream.Readable;
import js.node.stream.Writable;

import promhx.StreamPromises;

import util.streams.StreamTools;

using StringTools;

class ServiceStorageBase
	implements ServiceStorage
{
	public var type (get, never):StorageSourceType;
	public var _config :StorageDefinition;
	public var _rootPath :String;

	public function new() {}

	@post
	public function postInjection()
	{
		Assert.notNull(_config);
		setRootPath(_config.rootPath);
	}

	public function getConfig() :StorageDefinition
	{
		return Json.parse(Json.stringify(_config));
	}

	public function setConfig(config :StorageDefinition) :ServiceStorageBase
	{
		Assert.notNull(config);
		_config = config;
		postInjection();
		return this;
	}

	public function readFile(path :String) :Promise<IReadable>
	{
		return null;
	}

	public function exists(path :String) :Promise<Bool>
	{
		throw 'ServiceStorageBase.exists() Not implemented';
		return null;
	}

	public function readDir(?path :String) :Promise<IReadable>
	{
		return null;
	}

	public function writeFile(path :String, data :IReadable) :Promise<Bool>
	{
		return null;
	}

	public function copyFile(source :String, target :String) :Promise<Bool>
	{
		return null;
	}

	public function deleteFile(path :String) :Promise<Bool>
	{
		return null;
	}

	public function deleteDir(?path :String) :Promise<Bool>
	{
		return null;
	}

	public function listDir(?path :String) :Promise<Array<String>>
	{
		return null;
	}

	public function makeDir(?path :String) :Promise<Bool>
	{
		return null;
	}

	public function setRootPath(val :String) :ServiceStorage
	{
		_rootPath = val;
		if (_rootPath == null) {
			_rootPath = '';
		}
		_rootPath = ensureEndsWithSlash(_rootPath);
		return this;
	}

	public function getRootPath() :String
	{
		return _rootPath;// != null ? _rootPath : '';
	}

	public function appendToRootPath(path :String) :ServiceStorage
	{
		throw 'You need to override ServiceStorageBase.appendToRootPath()';
		return null;
	}

	public function close()
	{
		//Not needed
	}

	public function getPath(p :String) :String
	{
		if (p == null) {
			return _rootPath;
		} else if (p.startsWith('/')) {
			return p;
		} else {
			return Path.join(_rootPath, p);
		}
	}

	public function toString()
	{
		return '[StorageBase rootPath=$_rootPath]';
	}

	public function clone() :ServiceStorage
	{
		// TODO I'm not sure this is the correct way to make a clone in Haxe
		// TODO the S3 service should probably override this and keep the PkgCloud Client as a singleton
		var theCopy :ServiceStorageBase = Type.createEmptyInstance(Type.getClass(this));
		if (_config != null) {
			theCopy.setConfig(Json.parse(Json.stringify(_config)));
		}
		theCopy.setRootPath(_rootPath);
		return theCopy;
	}

	public function resetRootPath() :ServiceStorage
	{
		if (_config == null) {
			throw 'Unable to reset Storage Service w/o a config';
		}

		return setRootPath(_config.rootPath);
	}

	public function getExternalUrl(?path :String) :String
	{
		return path == null ? '' : path;
	}

	public function test() :Promise<ServiceStorageTestResult>
	{
		var randString = js.npm.shortid.ShortId.generate();
		var stream = StreamTools.stringToStream(randString);
		var clsNameTokens = Type.getClassName(Type.getClass(this)).split('.');
		var fileName = clsNameTokens[clsNameTokens.length - 1] + "Test";
		return writeFile(fileName, stream)
			.pipe(function(_) {
				return readFile(fileName)
					.pipe(function(stream) {
						return StreamPromises.streamToString(stream)
							.then(function(out) {
								var success = randString == out.trim();
								return {success:success, write:true, read:true, error:null};
							})
							.errorPipe(function(err) {
								return Promise.promise({success:false, write:true, read:false, error:Json.stringify(err)});
							});
					});
			})
			.errorPipe(function(err) {
				return Promise.promise({success:false, write:false, read:false, error:Json.stringify(err)});
			});
	}

	function get_type() :StorageSourceType
	{
		return _config.type;
	}

	function ensureEndsWithSlash(s :String) :String
	{
		if (s != null && s.length > 0 && s != '/' && !s.endsWith('/')) {
			return s + '/';
		} else {
			return s;
		}
	}
}