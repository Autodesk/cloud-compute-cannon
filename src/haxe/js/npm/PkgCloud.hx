package js.npm;

#if promhx
import promhx.Deferred;
import promhx.CallbackPromise;
import promhx.Promise;
import promhx.RetryPromise;
#end

import js.Node;
import js.Error;
import js.node.stream.Writable;
import js.node.stream.Readable;

@:enum
abstract ProviderType(String) {
  var amazon = 'amazon';
  var google = 'google';
}

//https://github.com/pkgcloud/pkgcloud/blob/master/docs/providers/amazon.md#using-compute
//https://github.com/pkgcloud/pkgcloud/blob/master/lib/pkgcloud/amazon/client.js
typedef ClientOptionsAmazon = {>ProviderCredentials,
	var keyId :String;
	var key :String;
	var region :String;
	@:optional var securityGroup :String;
	@:optional var securityGroupId :String;
	@:optional var serversUrl :String;
}

typedef ComputeServerCreateOptions = {}

typedef ComputeServerCreateOptionsAmazon = {>ComputeServerCreateOptions,
	@:optional var name :String;
	@:optional var image :Dynamic;
	@:optional var flavor :Dynamic;
}

@:enum
abstract PkgCloudComputeStatus(String) {
  var error = 'ERROR';
  var provisioning = 'PROVISIONING';
  var reboot = 'REBOOT';
  var running = 'RUNNING';
  var stopped = 'STOPPED';
  var terminated = 'TERMINATED';
  var unknown = 'UNKNOWN';
  var updating = 'UPDATING';
}

typedef PkgCloudServer = {
	var id :String;
	var name :String;
	var status :PkgCloudComputeStatus;
	var addresses :Dynamic;
	var imageId :String;
}

typedef PkgCloudServerAws = {>PkgCloudServer,
	var imageId :String;
	var launchTime :String; //Format example: Mon Jan 04 2016 10:05:07 GMT-0800 (PST)
	var flavorId :String;
	var original :Dynamic;
}

typedef Image = {
	var name :String;
}

typedef ComputeClient = {
	function getServers(cb :Null<Error>->Array<PkgCloudServer>->Void) :Void;
	function createServer(options :ComputeServerCreateOptions, cb :Null<Error>->PkgCloudServer->Void) :Void;
	function destroyServer(serverId :String, cb :Null<Error>->PkgCloudServer->Void) :Void;
	function getServer(serverId :String, cb :Null<Error>->PkgCloudServer->Void) :Void;
	function rebootServer(serverId :String, cb :Null<Error>->PkgCloudServer->Void) :Void;
	function getImages(cb :Null<Error>->Array<Image>->Void) :Void;
// client.getImage(imageId, function (err, image) { })
// client.destroyImage(image, function (err, ok) { })
// client.createImage(options, function (err, image) { })

// client.getFlavors(function (err, flavors) { })
// client.getFlavor(flavorId, function (err, flavor) { })
}

typedef Container = {
	var name :String;
	function create(options :Dynamic, cb :Null<Error>->Container->Void) :Void;
	function refresh(cb :Null<Error>->Container->Void) :Void;
	function destroy(cb :Null<Error>->Void) :Void;
	function upload(file :String, local :Dynamic, options :Dynamic, cb :Null<Error>->Void) :IWritable;
	function getFiles(cb :Null<Error>->Array<File>->Void) :Void;
	function removeFile(file :File, ?cb :Null<Error>->Void) :Void;
}

typedef File = {
	var name :String;
	var fullPath :String;
	var containerName :String;
	function remove(cb :Null<Error>->Void) :Void;
	function download(options :Dynamic, ?cb :Null<Error>->Void) :IReadable;
}

typedef StorageClient = {
	function getContainers(cb :Error->Array<Container>->Void) :Void;
	function createContainer(options :Dynamic, cb :Null<Error>->Container->Void) :Void;
	function destroyContainer(containerName :String, cb :Null<Error>->Void) :Void;
	function getContainer(containerName :String, cb :Null<Error>->Container->Void) :Void;

	function upload(options :Dynamic) :IWritable;
	function download(options :Dynamic, ?cb :Null<Error>->Void) :IReadable;
	function getFiles(container :Container, cb :Null<Error>->Array<File>->Void) :Void;
	function getFile(container :Container, fileName :String, cb :Null<Error>->File->Void) :Void;
	function removeFile(container :Container, file :File, ?cb :Null<Error>->Void) :Void;
}

typedef Credentials = {
}

typedef ProviderCredentials = { >Credentials,
	@:optional
	var provider :ProviderType;
}

typedef ProviderCredentialsLocal = { >ProviderCredentials,
	var baseLocalPath :String;
}

typedef ProviderLocal<T>  = {
	function createClient(credentials :ProviderCredentialsLocal) :T;
}

typedef ClientCreator<T> = {
	function createClient(credentials :Credentials) :T;
}

typedef ProviderClientCreator<T> = {
	function createClient(credentials :ProviderCredentials) :T;
}

typedef Provider = {
	var compute :ClientCreator<ComputeClient>;
	var storage :ClientCreator<StorageClient>;
	//Add more here as needed.
}

typedef Google = {
	var storage :ClientCreator<StorageClient>;
}

typedef Providers = {> Iterable<String>,
	var amazon :Provider;
	var azure :Provider;
	var digitalocean :Provider;
	var google :Provider;
	var local :Provider;
}

@:jsRequire('pkgcloud')
extern class PkgCloud extends js.node.events.EventEmitter<Dynamic>
{
	static public var providers :Providers;
#if promhx
	static public var compute :ClientCreator<ComputeClientP>;
	static public var storage :ClientCreator<StorageClientP>;
#else
	static public var compute :ClientCreator<ComputeClient>;
	static public var storage :ClientCreator<StorageClient>;
#end
}

#if promhx

class ClientImplCompute
{
	public static function getServers(client :ComputeClient) :Promise<Array<PkgCloudServer>>
	{
		var promise = new CallbackPromise();
		client.getServers(promise.cb2);
		return promise;
	}

	public static function createServer(client :ComputeClient, options :ComputeServerCreateOptions) :Promise<PkgCloudServer>
	{
		var promise = new CallbackPromise();
		client.createServer(options, promise.cb2);
		return promise;
	}

	public static function destroyServer(client :ComputeClient, serverId :String) :Promise<PkgCloudServer>
	{
		var promise = new CallbackPromise();
		client.destroyServer(serverId, promise.cb2);
		return promise;
	}

	public static function getServer(client :ComputeClient, serverId :String) :Promise<PkgCloudServer>
	{
		var promise = new CallbackPromise();
		client.getServer(serverId, promise.cb2);
		return promise;
	}

	public static function rebootServer(client :ComputeClient, serverId :String) :Promise<PkgCloudServer>
	{
		var promise = new CallbackPromise();
		client.rebootServer(serverId, promise.cb2);
		return promise;
	}


	public static function getImages(client :ComputeClient) :Promise<Array<Image>>
	{
		var promise = new CallbackPromise();
		client.getImages(promise.cb2);
		return promise;
	}
}

abstract ComputeClientP(ComputeClient) from ComputeClient
{
	inline static var RETRIES = 10;
	/* This value doubles on every retry attempt */
	inline static var RETRIES_INTERVAL = 200;
	inline public function new (s: ComputeClient)
		this = s;

	inline public function getServers() :Promise<Array<PkgCloudServer>>
	{
		return RetryPromise.pollDecayingInterval(ClientImplCompute.getServers.bind(this), RETRIES, RETRIES_INTERVAL, 'ComputeClient.getServers');
	}

	inline public function createServer(options :ComputeServerCreateOptions) :Promise<PkgCloudServer>
	{
		return RetryPromise.pollDecayingInterval(ClientImplCompute.createServer.bind(this, options), RETRIES, RETRIES_INTERVAL, 'ComputeClient.createServer');
	}

	inline public function destroyServer(serverId :String) :Promise<PkgCloudServer>
	{
		return RetryPromise.pollDecayingInterval(ClientImplCompute.destroyServer.bind(this, serverId), RETRIES, RETRIES_INTERVAL, 'ComputeClient.destroyServer');
	}

	inline public function getServer(serverId :String) :Promise<PkgCloudServer>
	{
		return RetryPromise.pollDecayingInterval(ClientImplCompute.getServer.bind(this, serverId), RETRIES, RETRIES_INTERVAL, 'ComputeClient.getServer');
	}

	inline public function rebootServer(serverId :String) :Promise<PkgCloudServer>
	{
		return RetryPromise.pollDecayingInterval(ClientImplCompute.rebootServer.bind(this, serverId), RETRIES, RETRIES_INTERVAL, 'ComputeClient.rebootServer');
	}


	inline public function getImages() :Promise<Array<Image>>
	{
		return RetryPromise.pollDecayingInterval(ClientImplCompute.getImages.bind(this), RETRIES, RETRIES_INTERVAL, 'ComputeClient.getImages');
	}
}

abstract StorageClientP(StorageClient) from StorageClient
{
	inline public function new (s: StorageClient)
		this = s;

	inline public function getContainers() :Promise<Array<Container>>
	{
		return ClientImplStorage.getContainers(this);
	}

	inline public function createContainer(options :Dynamic) :Promise<Container>
	{
		return ClientImplStorage.createContainer(this, options);
	}

	inline public function destroyContainer(containerName :String) :Promise<Bool>
	{
		return ClientImplStorage.destroyContainer(this, containerName);
	}

	inline public function getContainer(containerName :String) :Promise<Container>
	{
		return ClientImplStorage.getContainer(this, containerName);
	}

	inline public function upload(options :Dynamic) :IWritable
	{
		return ClientImplStorage.upload(this, options);
	}

	inline public function download(options :Dynamic) :IReadable
	{
		return ClientImplStorage.download(this, options);
	}

	inline public function getFiles(container :Container) :Promise<Array<File>>
	{
		return ClientImplStorage.getFiles(this, container);
	}

	inline public function getFile(container :Container, fileName :String) :Promise<File>
	{
		return ClientImplStorage.getFile(this, container, fileName);
	}

	inline public function removeFile(container :Container, file :File) :Promise<Bool>
	{
		return ClientImplStorage.removeFile(this, container, file);
	}
}

class ClientImplStorage
{
	public static function getContainers(client :StorageClient) :Promise<Array<Container>>
	{
		var promise = new CallbackPromise();
		client.getContainers(promise.cb2);
		return promise;
	}

	public static function createContainer(client :StorageClient, options :Dynamic) :Promise<Container>
	{
		var promise = new CallbackPromise();
		client.createContainer(options, promise.cb2);
		return promise;
	}

	public static function destroyContainer(client :StorageClient, containerName :String) :Promise<Bool>
	{
		var promise = new CallbackPromise();
		client.destroyContainer(containerName, promise.cb1);
		return promise
			.then(function(_) return true);
	}

	public static function getContainer(client :StorageClient, containerName :String) :Promise<Container>
	{
		var promise = new CallbackPromise();
		client.getContainer(containerName, promise.cb2);
		return promise;
	}

	public static function upload(client :StorageClient, options :Dynamic) :IWritable
	{
		return client.upload(options);
	}

	public static function download(client :StorageClient, options :Dynamic) :IReadable
	{
		return client.download(options);
	}

	public static function getFiles(client :StorageClient, container :Container) :Promise<Array<File>>
	{
		var promise = new CallbackPromise();
		client.getFiles(container, promise.cb2);
		return promise;
	}

	public static function getFile(client :StorageClient, container :Container, fileName :String) :Promise<File>
	{
		var promise = new CallbackPromise();
		client.getFile(container, fileName, promise.cb2);
		return promise;
	}

	public static function removeFile(client :StorageClient, container :Container, file :File) :Promise<Bool>
	{
		var promise = new CallbackPromise();
		client.removeFile(container, file, promise.cb1);
		return promise
			.then(function(_) return true);
	}
}
#end