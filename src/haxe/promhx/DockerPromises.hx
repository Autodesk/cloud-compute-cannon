package promhx;

import haxe.Json;

#if nodejs
import js.npm.docker.Docker;
import js.node.stream.Readable;
import js.node.stream.Readable.ReadableEvent;
#end

import promhx.Deferred;
import promhx.CallbackPromise;
import promhx.deferred.DeferredPromise;

import util.DockerUrl;

using promhx.PromiseTools;

class DockerPromises
{
	static var RETRIES = 8;
	static var RETRIES_TIME_INTERVAL = 40;

	public static function createContainer(docker :Docker, opts :CreateContainerOptions) :Promise<DockerContainer>
	{
		var promise = new promhx.CallbackPromise();
		docker.createContainer(opts, promise.cb2);
		return promise;
	}

	public static function listImages(docker :Docker) :Promise<Array<ImageData>>
	{
		var promise = new promhx.CallbackPromise();
		docker.listImages(promise.cb2);
		return promise;
	}

	public static function hasImage(docker :Docker, imageUrl :DockerUrl) :Promise<Bool>
	{
		return listImages(docker)
			.then(function(images) {
				return images.exists(function(e) {
					return e.RepoTags.exists(function(tag :DockerUrl) {
						return DockerUrlTools.matches(imageUrl, tag);
					});
				});
			});
	}

	public static function push(image :DockerImage, ?opts :{?tag :String}, ?auth :Dynamic) :Promise<Bool>
	{
		opts = opts == null ? {} : opts;
		var promise = new DeferredPromise();
		image.push(opts, function (err, stream: IReadable) {
			if (err != null) {
				Log.error('encountered error when push image: ${image.name} error: $err');
				promise.boundPromise.reject(err);
				return;
			}

			var errorsEncounteredInStream = [];

			// stream.on('close', function () {
			// it doesn't send the 'close' event - DEH 20151221
			stream.on(ReadableEvent.End, function () {
				if (errorsEncounteredInStream.length > 0) {
					promise.boundPromise.reject(errorsEncounteredInStream.length == 1 ? errorsEncounteredInStream[0] : errorsEncounteredInStream);
				} else {
					promise.resolve(true);
				}
			});

			stream.on(ReadableEvent.Data, function(buf :js.node.Buffer) {
				if (buf != null) {
					var bufferString = buf.toString();
					var data = Json.parse(bufferString);
					if (data.status != null) {
						if (data.status.startsWith('Status:')) {
							Log.info(data.status);
						}
					} else if (data.error != null) {
						Log.error('error: ${Json.stringify(data)}');
						errorsEncounteredInStream.push(data);
					} else {
						Log.error('Cannot handle stream data=$data');
					}
				}
			});
		}, auth);

		return promise.boundPromise;
	}

	public static function listContainers(docker :Docker, ?opts :ListContainerOptions) :Promise<Array<ContainerData>>
	{
		return promhx.RetryPromise.pollDecayingInterval(__listContainers.bind(docker, opts), RETRIES, RETRIES_TIME_INTERVAL, 'listContainers');
	}

	static function __listContainers(docker :Docker, ?opts :ListContainerOptions) :Promise<Array<ContainerData>>
	{
		var promise = new promhx.CallbackPromise();
		docker.listContainers(opts, promise.cb2);
		return promise;
	}

	public static function stopContainer(container :DockerContainer) :Promise<Bool>
	{
		var promise = new CallbackPromise();
		container.stop(promise.cb2);
		return promise
			.thenTrue();
	}

	public static function killContainer(container :DockerContainer) :Promise<Bool>
	{
		var promise = new CallbackPromise();
		container.kill(promise.cb2);
		return promise
			.thenTrue();
	}

	public static function removeContainer(container :DockerContainer, ?opts :RemoveContainerOpts) :Promise<Bool>
	{
		return promhx.RetryPromise.pollDecayingInterval(__removeContainer.bind(container, opts), RETRIES, RETRIES_TIME_INTERVAL, 'removeContainer');
	}

	public static function wait(container :DockerContainer) :Promise<{StatusCode:Int}>
	{
		var promise = new CallbackPromise();
		container.wait(promise.cb2);
		return promise;
	}

	public static function __removeContainer(container :DockerContainer, ?opts :RemoveContainerOpts) :Promise<Bool>
	{
		var promise = new CallbackPromise();
		container.remove(opts, promise.cb2);
		return promise
			.thenTrue();
	}

	public static function info(docker :Docker) :Promise<DockerInfo>
	{
		var promise = new promhx.CallbackPromise();
		docker.info(promise.cb2);
		return promise;
	}

	public static function inspect(container :DockerContainer) :Promise<ContainerInspectInfo>
	{
		var promise = new promhx.CallbackPromise();
		container.inspect(promise.cb2);
		return promise;
	}

	public static function pull(docker :Docker, image :String, ?opts :PullImageOptions) :Promise<Bool>
	{
		var promise = new DeferredPromise();
		docker.pull(image, opts, function (err, stream: IReadable) {
			if (err != null) {
				Log.error('encountered error when pulling image: $image error: $err');
				promise.boundPromise.reject(err);
				promise = null;
				return;
			}

			var errorEncounteredInStream :Bool = false;

			// stream.on('close', function () {
			// it doesn't send the 'close' event - DEH 20151221
			stream.on(ReadableEvent.End, function () {
				if (promise != null) {
					promise.resolve(!errorEncounteredInStream);
					promise = null;
				}
			});

			stream.on(ReadableEvent.Data, function(buf :js.node.Buffer) {
				if (buf != null) {
					var bufferString = buf.toString();
					var data :{status :String, id:String, error :Dynamic} = Json.parse(bufferString);
					if (data.status != null) {
						if (data.status.startsWith('Status:')) {
							Log.info(data.status);
						}
					} else if (data.error != null) {
						Log.error('error: ${Json.stringify(data)}');
						errorEncounteredInStream = true;
					} else {
						Log.error('Cannot handle stream data=$data');
					}
				}
			});
		});

		return promise.boundPromise;
	}

	public static function ping(docker :Docker) :Promise<Bool>
	{
		var promise = new CallbackPromise();
		trace('docker ping');
		docker.ping(promise.cb1);
		return promise.thenTrue();
	}
}