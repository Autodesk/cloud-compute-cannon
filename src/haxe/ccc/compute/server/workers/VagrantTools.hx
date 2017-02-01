package ccc.compute.server.workers;

import js.Node;
import js.node.Path;
import js.node.Fs;

import js.npm.fsextended.FsExtended;
import js.npm.vagrant.Vagrant;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

import util.streams.StdStreams;

using promhx.PromiseTools;

class VagrantTools
{
	public static function getMachine(path :String)
	{
		return Vagrant.create({cwd: path, env: Node.process.env});
	}

	public static function getMachineStatus(path :String) :Promise<VagrantStatusResult>
	{
		return promhx.RetryPromise.pollDecayingInterval(function() return __getMachineStatus(path), 5, 20, 'VagrantTools.getMachineStatus');
	}

	static function __getMachineStatus(path :String) :Promise<VagrantStatusResult>
	{
		var deferred = new promhx.deferred.DeferredPromise();
		var machine = getMachine(path);
		machine.status(function(err, out) {
			if (err != null) {
				Log.error('Failed status call on machine at path=$path err=$err');
				deferred.boundPromise.reject(err);
				return;
			}
			var status :VagrantStatusResult = Reflect.field(out, Reflect.fields(out)[0]);
			deferred.resolve(status);
		});
		return deferred.boundPromise;
	}

	public static function ensureVagrantBoxRunning(path :String, ?streams :StdStreams) :Promise<VagrantMachine>
	{
		// Log.info('Ensure vagrant machine running at $path');
		return getMachineStatus(path)
			.pipe(function(status) {
				var machine = getMachine(path);
				switch(status.status) {
					case NotCreated, PowerOff:
						var deferred = new promhx.deferred.DeferredPromise();
						var monitor = function(status) {
							if (streams != null) {
								streams.out.write(status + '');
							}
						}
						machine.on('progress', monitor);
						machine.up(function(err, out) {
							machine.removeListener('progress', monitor);
							if (err != null) {
								Log.error(err);
								deferred.boundPromise.reject(err);
								return;
							}
							if (streams != null) {
								streams.out.write(out);
							}
							deferred.resolve(machine);
						});
						return deferred.boundPromise;
					case Running:
						return Promise.promise(machine);
					case Aborted:
						return remove(path, false, streams)
							.pipe(function(_) {
								return ensureVagrantBoxRunning(path, streams);
							});
					default:
						throw 'Unhandled status ${status.status}';
				}
			});
	}

	public static function ensureVagrantBoxStopped(path :String, ?streams :StdStreams) :Promise<Bool>
	{
		// Log.info('Ensure vagrant machine stopped at $path');
		return getMachineStatus(path)
			.pipe(function(status) {
				var machine = getMachine(path);
				switch(status.status) {
					case NotCreated, PowerOff, Aborted, Saved:
						return Promise.promise(true);
					case Running:
						var deferred = new promhx.deferred.DeferredPromise();
						machine.halt(function(err, results) {
							if (err != null) {
								Log.error(err);
								if (streams != null) {
									streams.err.write(err + '');
								}
							}
							deferred.resolve(true);
						});
						return deferred.boundPromise;
					default:
						throw 'Unhandled status ${status.status}';
						return Promise.promise(true);
				}
			});
	}

	public static function remove(path :String, rmDir :Bool, ?streams :StdStreams) :Promise<Bool>
	{
		// Log.info('Removing vagrant machine at $path');
		var deferred = new promhx.deferred.DeferredPromise();
		var machine = getMachine(path);
		var monitor = function(status) {
			if (streams != null) {
				streams.out.write(status + '');
			}
		}
		machine.on('progress', monitor);
		machine.destroy(function(err, out) {
			machine.removeListener('progress', monitor);
			if (streams != null && out != null) {
				streams.out.write(out, 'utf8');
			}
			if (rmDir) {
				FsExtended.deleteDirSync(path);
			}
			if (err != null) {
				//In this case we're not rejecting the promise, since an error can be valid
				Log.error(err);
				deferred.resolve(false);
				return;
			}
			// Log.info('Machine destroyed down $path');
			deferred.resolve(true);
		});
		return deferred.boundPromise;
	}

	public static function removeAll(rootPath :String, rmDir :Bool, ?streams :StdStreams) :Promise<Bool>
	{
		if (!FsExtended.existsSync(rootPath)) {
			return Promise.promise(true);
		}
		var promise = new promhx.CallbackPromise<Array<String>>();
		FsExtended.listDirs(rootPath, {}, promise.cb2);
		return promise
			.pipe(function(dirs) {
				return Promise.whenAll(dirs.map(function(dir) return remove(Path.join(rootPath, dir), rmDir, streams)));
			})
			.thenTrue();
	}

	public static function shutdown(path :String, ?streams :StdStreams) :Promise<Bool>
	{
		// Log.info('Shutdown vagrant machine at $path');
		var deferred = new promhx.deferred.DeferredPromise();
		var machine = getMachine(path);
		var monitor = function(status) {
			if (streams != null) {
				streams.out.write(status + '');
			}
		}
		machine.on('progress', monitor);
		machine.halt(function(err, out) {
			machine.removeListener('progress', monitor);
			if (streams != null && out != null) {
				streams.out.write(out, 'utf8');
			}
			if (err != null) {
				Log.error(err);
				//In this case we're not rejecting the promise, since an error can be valid
				deferred.boundPromise.reject(err);
				return;
			}
			Log.info('Machine shut down $path');
			deferred.resolve(true);
		});
		return deferred.boundPromise;
	}
}