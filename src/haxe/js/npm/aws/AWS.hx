package js.npm.aws;

import js.node.events.EventEmitter;
import js.node.stream.Readable;
import js.node.stream.Writable;

typedef AWSConfig = {
	@:optional var keyId :String;
	@:optional var key :String;
	@:optional var sessionToken :String;
	@:optional var region :String;
	@:optional var sslEnabled :Bool;
	@:optional var maxRetries :Int;
	@:optional var logger :IWritable;
}

typedef AWSConfigObject = {
	function update(creds :AWSConfig) :Void;
}

typedef AWSS3File = {
	var Location :String;
}

typedef AWSBucketParams = {
	var Bucket :String;
}


typedef AWSS3ObjectParams = {
	var Bucket :String;
	var Key :String;
}

typedef AWSS3ListObjectParams = {>AWSBucketParams,
	@:optional var ContinuationToken :String;
	@:optional var Prefix :String;
}

extern class AWSS3Bucket
{
	public function upload(arg :{Body:IReadable}) :Void;//js.node.events.EventEmitter<Dynamic>;
}

extern class AWSS3Object
{
	@:overload(function(arg :{Body:IReadable}):AWSS3Object {})
	public function upload(arg :{Body:IReadable}, cb :Null<Error>->AWSS3File->Void) :js.node.events.EventEmitter<Dynamic>;

	public function send(cb :Null<Error>->AWSS3File->Void) :Void;

	public function createReadStream() :IReadable;
}

@:native("(require('aws-sdk').S3)")
extern class AWSS3
{
	public function new(config :Dynamic);

	// @:overload(function(p :Dynamic, opts:Dynamic, cb :Null<Error>->Dynamic->Void) :Void
	// @:overload(function(p :{Bucket:String,Key:String,Body:IReadable}, opts:Dynamic, cb :Null<Error>->Dynamic->Void) :Void
	public function upload(p :{Bucket:String,Key:String,Body:IReadable}, cb :Null<Error>->Dynamic->Void) :EventEmitter<Dynamic>;

	@:overload(function(p :AWSS3ObjectParams) :AWSS3Object {})
	public function getObject(p :AWSS3ObjectParams, cb :Null<Error>->Dynamic->Void) :Void;

	// http://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#headBucket-property
	public function headBucket(p :{Bucket :String}, cb :Null<Error>->Dynamic->Void) :Void;
	public function getBucketPolicy(p :{Bucket :String}, cb :Null<Error>->Dynamic->Void) :Void;

	// http://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#createBucket-property
	public function createBucket(p :Dynamic, cb :Null<Error>->Dynamic->Void) :Void;

	// http://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#listBuckets-property
	public function listBuckets(cb :Null<Error>->Dynamic->Void) :Void;

	public function deleteObject(p :AWSS3ObjectParams, cb :Null<Error>->Dynamic->Void) :Void;

	public function listObjectsV2(p :AWSS3ListObjectParams, cb :Null<Error>->Dynamic->Void) :Void;

	public function deleteObjects(p :Dynamic, cb :Null<Error>->Dynamic->Void) :Void;
}

@:jsRequire("aws-sdk")
extern class AWS
{
	public static var config :AWSConfigObject;

	@:overload(function(args :AWSBucketParams):AWSS3Bucket {})
	public static function S3(args: {params :AWSS3ObjectParams}) :AWSS3Object;
}