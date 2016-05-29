package js.npm;

import js.Node;
import js.node.Fs;
import js.node.Path;
import js.npm.FsExtended;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

class FsPromises
{
	public static function readFile(path :String) :Promise<String>
	{
		var deferred = new DeferredPromise();
		Fs.readFile(path, STRING_ENCODING, function(err :Dynamic, data :String) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			deferred.resolve(data);
		});
		return deferred.boundPromise;
	}

	public static function writeFile(s :String, path :String) :Promise<Bool>
	{
		var deferred = new DeferredPromise();
		FsExtended.createDir(Path.dirname(path), null, function(?err) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			Fs.writeFile(path, s, STRING_ENCODING, function(?err :Dynamic) {
				if (err != null) {
					deferred.boundPromise.reject(err);
					return;
				}
				deferred.resolve(true);
			});
		});
		return deferred.boundPromise;
	}

	public static function mkdir(path :String) :Promise<Bool>
	{
		var deferred = new DeferredPromise();
		FsExtended.ensureDir(path, null, function(?err) {
			if (err != null && untyped err.code != 'EEXIST') {
				Log.error(err);
				deferred.boundPromise.reject(err);
				return;
			}
			deferred.resolve(true);
		});
		return deferred.boundPromise;
	}

	public static function rmdir(path :String) :Promise<Bool>
	{
		var deferred = new DeferredPromise();
		FsExtended.deleteDir(path, function(?err) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			deferred.resolve(true);
		});
		return deferred.boundPromise;
	}

	public static function copyDir(source :String, target :String) :Promise<Bool>
	{
		var deferred = new DeferredPromise();
		FsExtended.copyDir(source, target, function(?err) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			deferred.resolve(true);
		});
		return deferred.boundPromise;
	}

	public static function writeFileTemplate(sourceTemplatePath :String, targetFilePath :String, ?args :Dynamic) :Promise<Bool>
	{
		return readFile(sourceTemplatePath)
			.pipe(function(templateString :String) {
				var template = new haxe.Template(templateString);
    			var output = template.execute(args);
    			return writeFile(output, targetFilePath);
			});
	}

	public static var STRING_ENCODING = {encoding:'utf8'};
}