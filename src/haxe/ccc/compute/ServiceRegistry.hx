package ccc.compute;

import ccc.compute.Definitions;
import ccc.compute.Definitions.Constants.*;
import ccc.compute.server.ServerCommands;
import ccc.storage.ServiceStorage;

import haxe.DynamicAccess;
import haxe.Json;

import js.node.http.*;
import js.node.http.ServerResponse;
import js.npm.RedisClient;
import js.npm.Docker;

import promhx.Promise;

import t9.abstracts.net.*;

import util.DockerTools;
import util.DockerRegistryTools;
import util.streams.StreamTools;

/**
 * Rest API and other internal tools for uploading and managing
 * docker images defined by jobs and used by workers.
 */
class ServiceRegistry
{
	// @inject public var _fs :ServiceStorage;
	// @inject public var _redis :RedisClient;

	@rpc({
		alias:'image-exists',
		doc:'Checks if a docker image exists in the registry'
	})
	public function imageExistsInLocalRegistry(image :DockerUrl) :Promise<Bool>
	{
		if (image == null) {
			throw 'Missing "image" parameter';
		}
		var repository = image.repository;
		var tag = image.tag;
		var host :Host = ConnectionToolsRegistry.getRegistryAddress();
		trace('imageExistsInLocalRegistry image=$image repository=$repository tag=$tag host=$host');
		return DockerRegistryTools.isImageIsRegistry(host, repository, tag);
	}

	@rpc({
		alias:'image-list',
		doc:'Checks if a docker image exists in the registry'
	})
	public function getAllImagesInRegistry() :Promise<DynamicAccess<Array<String>>>
	{
		var host :Host = ConnectionToolsRegistry.getRegistryAddress();
		return DockerRegistryTools.getRegistryImagesAndTags(host);
	}

	@rpc({
		alias:'image-url',
		doc:'Adds the registry host to the image url IF the image exists in the registry'
	})
	public function getCorrectImageUrl(image :DockerUrl) :Promise<DockerUrl>
	{
		if (image == null) {
			throw 'Missing "image" parameter';
		}
		return getFullDockerImageRepositoryUrl(image);
	}

	@rpc({
		alias:'image-push',
		doc:'Pushes a docker image (downloads it if needed) and tags it into the local registry for workers to consume.',
		args:{
			tag: {doc: 'Custom tag for the image', short:'t'},
			opts: {doc: 'ADD ME', short:'o'}
		}
	})
	public function pullRemoteImageIntoRegistry(image :String, ?tag :String, ?opts: PullImageOptions) :Promise<DockerUrl>
	{
		return ServerCommands.pushImageIntoRegistry(image, tag, opts);
	}

	/**
	 * If the docker image repository looks like 'myname/myimage', it might
	 * be an image actually already uploaded to the registry. However, workers
	 * need the full URL to the registry e.g. "<ip>:5001/myname/myimage".
	 * This function checks if the image is in the repository, and if so,
	 * ensures the host is part of the full URL.
	 * @param  url :DockerUrlBlob [description]
	 * @return     [description]
	 */
	public function getFullDockerImageRepositoryUrl(url :DockerUrl) :Promise<DockerUrl>
	{
		if (url.registryhost != null) {
			return Promise.promise(url);
		} else {
			return imageExistsInLocalRegistry(url)
				.then(function(exists) {
					if (!exists) {
						return url;
					} else {
						var registryHost :Host = ConnectionToolsRegistry.getRegistryAddress();
						url.registryhost = registryHost;
						return url;
					}
				});
		}
	}

	/**
	 * Some remote methods are not handled via JSON-RPC due to e.g.
	 * passing the content of the stream.
	 * @return [description]
	 */
	public function router() :js.node.express.Router
	{
		var router = js.node.express.Express.GetRouter();
		router.post('/build/*', buildDockerImageRouter);
		return router;
	}

	function buildDockerImageRouter(req :IncomingMessage, res :ServerResponse, next :?Dynamic->Void) :Void
	{
		var isFinished = false;
		res.on(ServerResponseEvent.Finish, function() {
			isFinished = true;
		});
		function returnError(err :String, ?statusCode :Int = 400) {
			Log.error(err);
			if (isFinished) {
				Log.error('Already returned ');
				Log.error(err);
			} else {
				isFinished = true;
				res.setHeader("content-type","application/json-rpc");
				res.writeHead(statusCode);
				res.end(Json.stringify({
					error: err
				}));
			}
		}

		var repositoryString :String = untyped req.params[0];
		trace('repositoryString=${repositoryString}');

		if (repositoryString == null) {
			returnError('You must supply a docker repository after ".../build/"', 400);
			return;
		}

		var repository :DockerUrl = repositoryString;
		trace('repository=${repository.toJson()}');

		try {
			if (repository.name == null) {
				returnError('You must supply a docker repository after ".../build/"', 400);
				return;
			}
			if (repository.tag == null) {
				returnError('All images must have a tag', 400);
				return;
			}
		} catch (err :Dynamic) {
			returnError(err, 500);
			return;
		}

		res.on('error', function(err) {
			Log.error({error:err});
		});
		res.writeHead(200);
		var throughStream = StreamTools.createTransformStream(function(chunk, encoding, forwarder) {
			res.write(chunk);
			forwarder(null, chunk);
		});
		ServerCommands.buildImageIntoRegistry(req, repository, throughStream)
			.then(function(imageUrl) {
				isFinished = true;
				res.end(Json.stringify({image:imageUrl}), 'utf8');
			})
			.catchError(function(err) {
				returnError('Failed to build image err=$err', 500);
			});
	}

	public function new() {}
}