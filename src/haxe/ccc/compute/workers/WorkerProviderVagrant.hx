package ccc.compute.workers;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;

import js.npm.docker.Docker;
import js.npm.fsextended.FsExtended;
import js.npm.FsPromises;
import js.npm.RedisClient;
import js.npm.ssh2.Ssh;
import js.npm.vagrant.Vagrant;

import promhx.Promise;
import promhx.deferred.DeferredPromise;
import promhx.RedisPromises;

import ccc.compute.ComputeTools;
import ccc.compute.InstancePool;
import ccc.compute.workers.VagrantTools;
import ccc.compute.workers.WorkerProviderVagrantTools;
import ccc.compute.workers.WorkerProviderVagrantTools as Tools;

import util.SshTools;

import t9.abstracts.net.*;
import t9.abstracts.time.Minutes;

using StringTools;
using ccc.compute.ComputeTools;
using promhx.PromiseTools;
using util.MapTools;
using Lambda;

typedef ServiceConfigurationWorkerProviderVagrant = {>ServiceConfigurationWorkerProvider,
	var rootPath :String;
}

class WorkerProviderVagrant extends WorkerProviderBase
{
	public static function destroyAllVagrantMachines() :Promise<Bool>
	{
		if (FsExtended.existsSync(ROOT_PATH)) {
			return VagrantTools.removeAll(ROOT_PATH, true);
		} else {
			return Promise.promise(true);
		}
	}

	public static var ROOT_PATH = 'tmp/vagrantProvider';

	var rootPath (get, null) :String;
	var _isDisposed = false;

	public function new(?config :ServiceConfigurationWorkerProvider)
	{
		super(config);
		this.id = ServiceWorkerProviderType.vagrant;
		if (_config == null) {
			_config = {
				type: ServiceWorkerProviderType.vagrant,
				minWorkers: 0,
				maxWorkers: 2,
				priority: 1,
				billingIncrement: new Minutes(0)
			};
		}
		var vagrantConfig :ServiceConfigurationWorkerProviderVagrant = cast _config;
		vagrantConfig.rootPath = ROOT_PATH;
	}

	@post
	override public function postInjection() :Promise<Bool>
	{
		FsExtended.ensureDirSync(rootPath);
		_ready = super.postInjection()
			.pipe(function(_) {
				return Tools.addIpAddressToPool(_redis, rootPath);
			});
		return _ready;
	}

	override public function createWorker() :Promise<WorkerDefinition>
	{
		var promise = super.createWorker();
		if (promise != null) {
			return promise;
		} else {
			return __createWorker();
		}
	}

	/** Completely remove the vagrant machine */
	override function shutdownWorker(workerId :MachineId) :Promise<Bool>
	{
		var path :VagrantPath = WorkerProviderVagrantTools.getVagrantBoxPath(rootPath, workerId);
		return WorkerProviderVagrantTools.removeMachineFromPool(_redis, path);
	}

	function __createWorker() :Promise<WorkerDefinition>
	{
		return Tools.addMachine(_redis, rootPath, null)
			.errorPipe(function(err) {
				Log.error('__createWorker err=$err');
				throw(err);
			});
	}

	override public function updateConfig(config :ServiceConfigurationWorkerProvider) :Promise<Bool>
	{
		var vagrantConfig :ServiceConfigurationWorkerProviderVagrant = cast config;
		vagrantConfig.rootPath = ROOT_PATH;
		return super.updateConfig(config);
	}

	override public function dispose() :Promise<Bool>
	{
		_isDisposed = true;
		return super.dispose();
	}

	override public function shutdownAllWorkers() :Promise<Bool>
	{
		return destroyAllVagrantMachines();
	}

	#if debug public #end
	override function verifyWorkerExists(workerId :MachineId) :Promise<Bool>
	{
		var path :VagrantPath = WorkerProviderVagrantTools.getVagrantBoxPath(rootPath, workerId);
		return Promise.promise(path != null);
	}

	inline function getConfig() :ServiceConfigurationWorkerProviderVagrant
	{
		return cast _config;
	}

	inline function get_rootPath() :String
	{
		return getConfig().rootPath;
	}
}
