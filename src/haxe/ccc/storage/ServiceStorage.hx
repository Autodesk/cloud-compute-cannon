package ccc.storage;

import promhx.Promise;

import js.node.stream.Readable;
import js.node.stream.Writable;

interface ServiceStorage
{
	var type (get, never):StorageSourceType;
	function readFile(uri :String) :Promise<IReadable>;
	function exists(uri :String) :Promise<Bool>;
	/* Returns a tgz stream */
	function readDir(?uri :String) :Promise<IReadable>;
	function writeFile(uri :String, data :IReadable) :Promise<Bool>;
	function getFileWritable(uri :String) :Promise<IWritable>;
	function deleteFile(uri :String) :Promise<Bool>;
	function deleteDir(?uri :String) :Promise<Bool>;
	function listDir(?uri :String) :Promise<Array<String>>;
	function makeDir(?uri :String) :Promise<Bool>;
	function setRootPath(val :String) :ServiceStorage;
	function getRootPath() :String;
	function close() :Void;
	function appendToRootPath(path :String) :ServiceStorage;
	/**
	 * For PkgCloud etc this is e.g. the S3 base url. For most others,
	 * this is an empty string since the underlying storage mechanisms cannot
	 * be accessed outside the service object.
	 * @return [description]
	 */
	function getExternalUrl(?path :String) :String;

#if debug
	var _rootPath :String;
#end

	function toString() :String;

	function clone() :ServiceStorage;
	function resetRootPath() :ServiceStorage;
}