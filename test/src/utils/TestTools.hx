package utils;

import js.Node;
import js.node.child_process.ChildProcess;
import js.node.ChildProcess;
import js.node.Path;
import js.node.Fs;
import js.node.Http;
import js.npm.FsPromises;
import js.npm.fsextended.FsExtended;
import js.npm.RedisClient;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.RequestPromises;

import ccc.compute.server.JobTools;
import ccc.storage.ServiceStorage;
import ccc.storage.StorageTools;
import ccc.compute.server.ComputeQueue;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;

typedef ServerCreationStuff = {
	var app :js.npm.Express;
	var server :js.node.http.Server;
}

class TestTools
{
	public static function forkServerCompute(?env :Dynamic, ?disableLogging :Bool = true) :Promise<js.node.child_process.ChildProcess>
	{
		//Create a server in a forker process
		var promise = new DeferredPromise();

		env = env != null ? env : Reflect.copy(js.Node.process.env);
		if (disableLogging) {
			Reflect.setField(env, ENV_VAR_DISABLE_LOGGING, "true");
		}

		var serverChildProcess = ChildProcess.fork('$BUILD_DIR_SERVER/$APP_SERVER_FILE', {env: env, silent:true});
		serverChildProcess.on(ChildProcessEvent.Message, function(message, sendHandle) {
			if (message == IPC_MESSAGE_READY) {
				promise.resolve(serverChildProcess);
			}
		});
		serverChildProcess.on(ChildProcessEvent.Error, function(err) {
			Log.error({f:'forkServerCompute', error:err});
			if (!promise.isResolved()) {
				promise.boundPromise.reject(err);
			}
		});
		serverChildProcess.stdout.pipe(Node.process.stdout);
		serverChildProcess.stderr.pipe(Node.process.stderr);
		return promise.boundPromise;
	}

	public static function killForkedServer(serverProcess: js.node.child_process.ChildProcess) :Promise<Bool>
	{
		var promise = new DeferredPromise();
		serverProcess.once('exit', function(e) {
			promise.resolve(true);
		});
		serverProcess.kill('SIGKILL');
		return promise.boundPromise;
	}

	public static function whenQueueisEmpty(redis :RedisClient) :Promise<Bool>
	{
		var deferred = new DeferredPromise();

		var id = null;
		var pendingCount = 0;
		var workingCount = 0;
		id = Node.setInterval(function() {
			ComputeQueue.toJson(redis)
				.then(function(jsonDump:QueueJson) {
					var currentPendingCount = jsonDump.pending.length;
					var currentWorkingCount = jsonDump.working.length;
					if (currentWorkingCount != workingCount || currentPendingCount != pendingCount) {
						pendingCount = currentPendingCount;
						workingCount = currentWorkingCount;
					}
					if (workingCount == 0 && pendingCount == 0) {
						Node.clearInterval(id);
						deferred.resolve(true);
					}
				});
		}, 50);

		return deferred.boundPromise;
	}

	public static function createServer(port :Int) :Promise<ServerCreationStuff>
	{
		var deferred = new DeferredPromise();
		var app = new js.npm.Express();
		var server = Http.createServer(cast app);
		server.listen(port, function() {
			deferred.resolve({app:app, server:server});
		});
		return deferred.boundPromise;
	}

	public static function getDateString() :String
	{
		return Date.now().format("%d__%H_%M__%S_" + (Std.int(Math.random() * 100000)));
	}

	public static function createVirtualJob(id :String)
	{
		var jobId :JobId = id;
		// var computeJobId :ComputeJobId = 'computeid_${id}';

		var dockerJob :DockerJobDefinition = {
			jobId: jobId,
			// computeJobId: computeJobId,
			worker: null,
			image: {type:DockerImageSourceType.Context, value:'/fake'},//, options:{t:computeJobId}},
			inputs: [],
			// inputDirectory: '/fake/inputs',
			// outputDirectory: '/fake/outputs',
			// inputSource: {type:StorageSourceType.Local, basePath:'/fake'},
			// outputTarget: {type:StorageSourceType.Local, basePath:'/fake'}
		};

		var job :QueueJobDefinitionDocker = {
			id: jobId,
			// computeJobId: computeJobId,
			item: dockerJob,
			parameters: {cpus:1, maxDuration:1000},
			worker: null
		}
		return job;
	}

	public static function createLocalJob(id :String, contextPath :String, inputsPath :String)
	{
		var jobId :JobId = id;
		var computeJobId :ComputeJobId = JobTools.generateComputeJobId(jobId);

		var dockerJob :DockerJobDefinition = {
			jobId: jobId,
			computeJobId: computeJobId,
			worker: null,
			image: {type:DockerImageSourceType.Context, value:contextPath, optionsBuild:{t:computeJobId}},
			inputs: FsExtended.listFilesSync(inputsPath),
		};

		var job :QueueJobDefinitionDocker = {
			id: jobId,
			computeJobId: computeJobId,
			item: dockerJob,
			parameters: {cpus:1, maxDuration:60000 * 10},
			worker: null
		}
		return job;
	}
}