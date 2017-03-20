package util;

import js.Node;
import js.node.Fs;
import js.node.Path;
import js.node.Http;
import js.node.http.*;
import js.npm.busboy.Busboy;
import js.npm.fsextended.FsExtended;

import promhx.Promise;
import promhx.CallbackPromise;
import promhx.deferred.DeferredPromise;
import promhx.StreamPromises;

class MultiformTools
{
	public static function pipeFilesToFolder(folder :String, req :IncomingMessage, ?fieldSize :Float = 10737418240) :Promise<Array<String>>
	{
		return ensureDir(folder)
			.pipe(function(_) {
				var promise = new DeferredPromise();
				var files = [];

				var tenGBInBytes = 10737418240;
				fieldSize = fieldSize != null ? fieldSize : tenGBInBytes;
				var busboy = new Busboy({headers:req.headers, limits:{fieldNameSize:500, fieldSize:fieldSize}});
				var deferredFieldHandling = [];//If the fields come in out of order, we'll have to handle the non-JSON-RPC subsequently
				var promises = [];
				busboy.on(BusboyEvent.File, function(fieldName, stream, fileName, encoding, mimetype) {
					if (promise == null) {
						return;
					}
					files.push(fieldName);
					var filePath = Path.join(folder, fieldName);
					var fileDir = Path.dirname(filePath);
					ensureDir(fileDir)
						.then(function(_) {
							var writeStream = Fs.createWriteStream(filePath);
							promises.push(StreamPromises.pipe(stream, writeStream));
						})
						.catchError(function(err) {
							if (promise != null) {
								promise.boundPromise.reject(err);
								promise = null;
							} else {
#if nodejs
								Node.console.error(err);
#else
								trace(err);
#end
							}
						});
				});
				busboy.on(BusboyEvent.Field, function(fieldName, val, fieldnameTruncated, valTruncated) {
					if (promise == null) {
						return;
					}
					files.push(fieldName);
					var filePath = Path.join(folder, fieldName);
					var fileDir = Path.dirname(filePath);
					ensureDir(fileDir)
						.then(function(_) {
							var p = new CallbackPromise();
							Fs.writeFile(filePath, val, {}, p.cb1);
							promises.push(p);
						})
						.catchError(function(err) {
							if (promise != null) {
								promise.boundPromise.reject(err);
								promise = null;
							} else {
#if nodejs
								Node.console.error(err);
#else
								trace(err);
#end
							}
						});
				});

				busboy.on(BusboyEvent.Finish, function() {
					if (promise == null) {
						return;
					}
					Promise.whenAll(promises)
						.then(function(_) {
							promise.resolve(files);
							promise = null;
						})
						.catchError(function(err) {
							promise.boundPromise.reject(err);
						});
				});
				busboy.on(BusboyEvent.PartsLimit, function() {
#if nodejs
								Node.console.error('BusboyEvent ${BusboyEvent.PartsLimit}');
#else
								trace('BusboyEvent ${BusboyEvent.PartsLimit}');
#end
				});
				busboy.on(BusboyEvent.FilesLimit, function() {
#if nodejs
					Node.console.error('BusboyEvent ${BusboyEvent.FilesLimit}');
#else
					trace('BusboyEvent ${BusboyEvent.FilesLimit}');
#end
				});
				busboy.on(BusboyEvent.FieldsLimit, function() {
#if nodejs
					Node.console.error('BusboyEvent ${BusboyEvent.FieldsLimit}');
#else
					trace('BusboyEvent ${BusboyEvent.FieldsLimit}');
#end
				});
				busboy.on('error', function(err) {
					if (promise != null) {
						promise.boundPromise.reject(err);
						promise = null;
					} else {
#if nodejs
						Node.console.error(err);
#else
						trace(err);
#end
					}
				});
				req.pipe(busboy);

				return promise.boundPromise;
		});
	}

	inline static function ensureDir(path :String) :Promise<Bool>
	{
		var promise = new CallbackPromise();
		FsExtended.ensureDir(path, null, promise.cb1);
		return promise;
	}
}