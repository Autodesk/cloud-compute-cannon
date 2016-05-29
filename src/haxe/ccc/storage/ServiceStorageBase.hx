package ccc.storage;

import haxe.Json;

import js.node.Path;
import js.node.stream.Readable;
import js.node.stream.Writable;

import promhx.Promise;

import ccc.storage.ServiceStorage;
import ccc.storage.StorageTools;

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
		Assert.notNull(_config.rootPath);
		_rootPath = _config.rootPath;
	}

	public function setConfig(config :StorageDefinition) :ServiceStorageBase
	{
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
		throw 'Not implemented';
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

	public function getFileWritable(path :String) :Promise<IWritable>
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
		return this;
	}

	public function getRootPath() :String
	{
		return _rootPath;
	}

	public function appendToRootPath(path :String) :ServiceStorage
	{
		return null;
	}

	public function close()
	{
		//Not needed
	}

	public function getPath(p :String) :String
	{
		if (p != null && p.startsWith('/')) {
			return p;
		} else {
			Assert.notNull(_rootPath);
			return p == null ? _rootPath : Path.join(_rootPath, p);
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

		return this.setRootPath(_config.rootPath);
	}

	public function getExternalUrl(?path :String) :String
	{
		return path == null ? '' : path;
	}

	inline function get_type() :StorageSourceType
	{
		return _config.type;
	}
}