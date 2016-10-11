package ccc.storage;

/**
 CORS configuration:

<?xml version="1.0" encoding="UTF-8"?>
<CORSConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
    <CORSRule>
        <AllowedOrigin>*</AllowedOrigin>
        <AllowedMethod>GET</AllowedMethod>
        <AllowedMethod>PUT</AllowedMethod>
        <AllowedMethod>POST</AllowedMethod>
        <AllowedMethod>DELETE</AllowedMethod>
        <AllowedMethod>HEAD</AllowedMethod>
        <AllowedHeader>*</AllowedHeader>
    </CORSRule>
</CORSConfiguration>

Bucket policy (where <USER> is the id of the user account, and
<BUCKET_NAME> is the name of the S3 bucket:

{
	"Version": "2008-10-17",
	"Statement": [
		{
			"Sid": "",
			"Effect": "Allow",
			"Principal": {
				"AWS": "arn:aws:iam::763896067184:user/<USER>"
			},
			"Action": [
				"s3:ListBucket",
				"s3:GetBucketLocation"
			],
			"Resource": "arn:aws:s3:::<BUCKET_NAME>"
		},
		{
			"Sid": "",
			"Effect": "Allow",
			"Principal": {
				"AWS": "arn:aws:iam::763896067184:user/<USER>"
			},
			"Action": [
				"s3:PutObject",
				"s3:GetObject",
				"s3:DeleteObject",
				"s3:DeleteObjectVersion",
				"s3:RestoreObject",
				"s3:GetObjectVersion"
			],
			"Resource": "arn:aws:s3:::<BUCKET_NAME>/*"
		},
		{
			"Sid": "",
			"Effect": "Allow",
			"Principal": "*",
			"Action": "s3:GetObject",
			"Resource": "arn:aws:s3:::<BUCKET_NAME>/*"
		}
	]
}
 */

import ccc.compute.Definitions;
import ccc.storage.ServiceStorage;
import ccc.storage.*;

import js.node.stream.Readable;
import js.node.stream.Writable;
import js.node.Fs;
import js.npm.aws.AWS;
import js.npm.fsextended.FsExtended;

import promhx.Promise;
import promhx.PromiseTools;
import promhx.StreamPromises;
import promhx.deferred.DeferredPromise;

using Lambda;
using StringTools;

class ServiceStorageS3 extends ServiceStorageBase
{
	var _containerName :String = "bionano-platform-test"; // we always need a bucket
	var _httpAccessUrl :String;
	var _S3 :AWSS3;
	var _initialized :Promise<Bool>;
	var _S3Config :ccc.docker.dataxfer.DockerDataTools.S3Credentials;


	private static var precedingSlash = ~/^\/+/;
	private static var endingSlash = ~/\/+$/;
	private static var extraSlash = ~/\/{2,}/g;
	private static var splitRegEx = ~/\/+/g;
	private static var replaceChar :String = "--";

	static var TEMP_FILE_PATH_DIR = '/tmp';
	static var TEMP_FILE_PATH_PREFIX = 'tmpfileS3';
	static var TEMP_FILES_CLEANED = false;

	public function new()
	{
		super();
	}

	override public function toString()
	{
		return '[StorageS3 _rootPath=$_rootPath container=${_containerName} _httpAccessUrl=${_httpAccessUrl}]';
	}

	public function getS3Credentials() :ccc.docker.dataxfer.DockerDataTools.S3Credentials
	{
		return Json.parse(Json.stringify(_S3Config));
	}

	function initialized() :Promise<Bool>
	{
		if (_initialized == null) {
			if (!TEMP_FILES_CLEANED) {
				TEMP_FILES_CLEANED = true;
				//Remove prior tmp files
				var filterStartingWith = '${TEMP_FILE_PATH_DIR}/${TEMP_FILE_PATH_PREFIX}';
				var existingTmpFiles = FsExtended.listAllSync(TEMP_FILE_PATH_DIR,
					{
						recursive:false,
						prependDir:true,
						filter:function(itemPath :String, stat:Dynamic) {
							return itemPath.startsWith(filterStartingWith);
						}
					});
				existingTmpFiles.iter(function(path) {
					try {
						traceYellow('Deleting $path');
						FsExtended.deleteFileSync(path);
					} catch(e :Dynamic) {
						Log.warn('Could not delete prior tmp file=$path err=$e');
					}
				});
			}

			var promise = new DeferredPromise();
			_initialized = promise.boundPromise;
			_S3.getBucketPolicy({Bucket:_containerName}, function(err, data) {
				if (err != null) {
					//For now, throw an error and crash. S3 buckets need to be
					//set up manually for now
					promise.boundPromise.reject(err);
					//No bucket exists, let's create one
					// var createBucketOptions = {
					// 	Bucket: _containerName,
					// 	ACL: 'public-read',
					// 	CreateBucketConfiguration: {
					// 		LocationConstraint: _config.credentials.region,
					// 	},
					// 	GrantFullControl: 'FULL_CONTROL'
					// }
					// _S3.createBucket(createBucketOptions, function(err, result) {
					// 	if (err != null) {
					// 		promise.boundPromise.reject(err);
					// 	} else {
					// 		promise.resolve(true);
					// 	}
					// });
				} else {
					promise.resolve(true);
				}
			});
		}
		return _initialized;
	}

	function getClient() :AWSS3
	{
		return _S3;
	}

	public function getContainerName(?options: Dynamic) :String
	{
		return _containerName;
	}

	override public function setConfig(config :StorageDefinition) :ServiceStorageBase
	{
		Assert.notNull(config.container);
		Assert.notNull(config.credentials);
		Assert.notNull(config.container);

		_containerName = config.container;

		var awsConfig = {
			accessKeyId: config.credentials.accessKeyId != null ? config.credentials.accessKeyId : config.credentials.keyId,
			secretAccessKey: config.credentials.secretAccessKey != null ? config.credentials.secretAccessKey : config.credentials.key,
			region: config.credentials.region,
			maxRetries: config.credentials.maxRetries
		}
		_S3Config = {keyId:awsConfig.accessKeyId, key:awsConfig.secretAccessKey, region:awsConfig.region, bucket:config.container, extraS3SyncParameters:config.extraS3SyncParameters};

		Assert.notNull(awsConfig.accessKeyId);
		Assert.notNull(awsConfig.secretAccessKey);

		Sys.environment()['AWS_S3_KEYID'] = awsConfig.accessKeyId;
		Sys.environment()['AWS_S3_KEY'] = awsConfig.secretAccessKey;
		Sys.environment()['AWS_S3_BUCKET'] = config.container;

		_httpAccessUrl = ensureEndsWithSlash(config.httpAccessUrl != null ? config.httpAccessUrl : 'https://${_containerName}.s3.amazonaws.com/');
		_S3 = new AWSS3(awsConfig);

		return super.setConfig(config);
	}

	override public function clone() :ServiceStorage
	{
		var copy = new ServiceStorageS3();
		var config = Reflect.copy(_config);
		config.httpAccessUrl = _httpAccessUrl;
		config.container = _containerName;
		config.rootPath = _rootPath;
		//This avoids cop
		copy.setConfig(config);
		return copy;
	}

	override public function exists(path :String) :Promise<Bool>
	{
		path = getPath(path);
		return initialized()
			.pipe(function(_) {
				var promise = new DeferredPromise();
				var params = {Bucket: _containerName, Key: path};
				_S3.headObject(params, function(err, data) {
					if (err != null && Reflect.field(err, 'code') == 'NotFound') {
						promise.resolve(false);
					} else if (err != null) {
						promise.boundPromise.reject(err);
					} else {
						promise.resolve(true);
					}
				});
				return promise.boundPromise;
			});
	}

	override public function readFile(path :String) :Promise<IReadable>
	{
		return exists(path)
			.pipe(function(file_exists) {
				if (file_exists) {
					path = getPath(path);
					var promise = new DeferredPromise();
					var params = {Bucket: _containerName, Key: path};
					promise.resolve(_S3.getObject(params).createReadStream());
					return promise.boundPromise;
				} else {
					return PromiseTools.error('Does not exist: $path');
				}
			});
	}

	override public function readDir(?path :String) :Promise<IReadable>
	{
		throw 'readDir(...) Not implemented';
		return null;
	}

	override public function writeFile(path :String, data :IReadable) :Promise<Bool>
	{
		Assert.notNull(data);
		path = getPath(path);
		var tempFileName :String = null;
		var cleanup = function() {
			if (tempFileName != null) {
				Node.setTimeout(function() {
					if (tempFileName != null) {
						Fs.unlink(tempFileName, function(err) {
							//Ignored
						});
						tempFileName = null;
					}
				}, 1000);
			}
		}
		return initialized()
			.pipe(function(_) {
				if (Reflect.hasField(data, 'read')) {
					return Promise.promise(data);
				} else {
					var tempFileToken = js.node.Path.basename(path);
					tempFileName = '${TEMP_FILE_PATH_DIR}/${TEMP_FILE_PATH_PREFIX}_${js.npm.shortid.ShortId.generate()}_${tempFileToken}';
					return StreamPromises.pipe(data, Fs.createWriteStream(tempFileName), [WritableEvent.Finish], 'ServiceStorageS3.writeFile $path')
						.then(function(done) {
							try {
								Fs.accessSync(tempFileName);//Throws if there is an accessibility issue
								return cast Fs.createReadStream(tempFileName);
							} catch(err :Dynamic) {
								Log.warn('Coping file to S3, coping to disk first, but there was no data, so no file stream $tempFileName');
								return null;
							}
						});
				}
			})
			.pipe(function(stream) {
				if (stream != null) {
					var promise = new DeferredPromise();
					var params = {Bucket: _containerName, Key: path, Body: stream};
					var eventDispatcher = _S3.upload(params, function(err, result) {
						if (err != null) {
							promise.boundPromise.reject(err);
						} else {
							promise.resolve(true);
						}
					});
					return promise.boundPromise;
				} else {
					return Promise.promise(true);
				}
				// This can be integrated later
				// eventDispatcher.on('httpUploadProgress', function(evt) {
				// 	trace('Progress:', evt.loaded, '/', evt.total);
				// });
			})
			.then(function(result) {
				cleanup();
				return result;
			})
			.errorPipe(function(err) {
				cleanup();
				return PromiseTools.error(err);
			});
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
		path = getPath(path);
		return initialized()
			.pipe(function(_) {
				var promise = new DeferredPromise();
				var params = {Bucket: _containerName, Key: path};
				_S3.deleteObject(params, function(err, result) {
					if (err != null) {
						promise.boundPromise.reject(err);
					} else {
						promise.resolve(true);
					}
				});
				return promise.boundPromise;
			});
	}

	override public function deleteDir(?path :String) :Promise<Bool>
	{
		return listDirS3(path)
			.pipe(function(fileList) {
				if (fileList.length > 0) {
					var promise = new DeferredPromise();
					var params = {Bucket: _containerName,
						Delete: {
							Objects:fileList.map(function(f) {
								return {
									Key:f
								}
							})
						}
					};
					_S3.deleteObjects(params, function(err, result) {
						if (err != null) {
							promise.boundPromise.reject(err);
						} else {
							promise.resolve(true);
						}
					});
					return promise.boundPromise;
				} else {
					return Promise.promise(true);
				}
			});
	}

	override public function listDir(?path :String) :Promise<Array<String>>
	{
		path = getPath(path);
		return listDirS3(path)
			.then(function(files) {
				return files.map(function(f) {
					f = path != null ? f.substr(path.length) : f;
					if (f.startsWith('/')) {
						f = f.substr(1);
					}
					return f;
				});
			});
	}

	function listDirS3(?path :String) :Promise<Array<String>>
	{
		return initialized()
			.pipe(function(_) {
				var promise = new DeferredPromise();
				var params = {Bucket: _containerName, Prefix: path, ContinuationToken:null};
				var continuationToken :String = null;

				var fileList = [];

				var getNext = null;
				getNext = function() {
					_S3.listObjectsV2(params, function(err, result) {
						if (err != null) {
							promise.boundPromise.reject(err);
						} else {
							var arr :Array<{Key:String}> = result.Contents;
							for (f in arr) {
								fileList.push(f.Key);
							}
							if (result.NextContinuationToken != null && result.IsTruncated) {
								params.ContinuationToken = result.NextContinuationToken;
								getNext();
							} else {
								promise.resolve(fileList);
							}
						}
					});
				}
				getNext();
				return promise.boundPromise;
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
		if (path != null && path.startsWith('http')) {
			return path;
		}
		path = getPath(path);
		if (_httpAccessUrl != null) {
			return _httpAccessUrl + path;
		} else {
			return path;
		}
	}

	static function isBucket(s3 :AWSS3, bucket :String) :Promise<Bool>
	{
		var promise = new DeferredPromise();


		return promise.boundPromise;
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