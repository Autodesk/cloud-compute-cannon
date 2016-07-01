package ccc.storage;

/**
 * Given a an abstract ServiceStorage, wraps a REST API
 * on top of it. This way, you can serve up files from
 * any implementation of ServiceStorage
 */

import haxe.Json;
import js.npm.express.Request;
import js.npm.express.Response;
import js.npm.express.Middleware;
import js.npm.express.Router;

import ccc.storage.ServiceStorage;

using StringTools;

class StorageRestApi
{
	static public function read(storage :ServiceStorage, req :Request, res :Response, next :MiddlewareNext)
	{
		var file = req.path;
		if (file == null) {
			next();
			return;
		}
		if (file.startsWith('/')) {
			file = file.substr(1);
		}
		storage.readFile(file)
			.then(function(stream) {
				stream.once('error', function(err) {
					Log.error({error:err, file:file, message:'Error reading file'});
					res.status(500)
						.send(Json.stringify({
							file:file,
							error:'Could not read file'
						}));
				});
				stream.pipe(res);
			})
			.catchError(function(err) {
				res.setHeader('Content-Type', 'application/json');
				Log.error({error:err, file:file, message:'Error reading file'});
				res.status(500)
					.send(Json.stringify({
						file:file,
						error:'Could not read file'
					}));
			});
	}

	static public function write(storage :ServiceStorage, req :Request, res :Response, next :MiddlewareNext)
	{
		var file = req.path;
		if (file == null) {
			next();
			return;
		}
		if (file.startsWith('/')) {
			file = file.substr(1);
		}

		if (file == null) {
			res.setHeader('Content-Type', 'application/json');
			res.status(400)
				.send(Json.stringify({
					error: 'No URL parameter "file"'
				}));
			return;
		}
		storage.writeFile(file, cast req)
			.then(function(success) {
				res.setHeader('Content-Type', 'application/json');
				res.status(200).send(RESPONSE_OK);
			})
			.catchError(function(err) {
				res.setHeader('Content-Type', 'application/json');
				res.status(500)
					.send(Json.stringify({
						error: err
					}));
			});
	}

	static public function router(storage :ServiceStorage) :Router
	{
		var router = new Router();
		router.get('/*', read.bind(storage));
		router.post('/*', write.bind(storage));
		return router;
	}

	static public function staticFileRouter(storage :ServiceStorage) :Router
	{
		var router = new Router();
		router.get('/*', read.bind(storage));
		return router;
	}

	inline static var RESPONSE_OK = '{"response":"OK"}';
}