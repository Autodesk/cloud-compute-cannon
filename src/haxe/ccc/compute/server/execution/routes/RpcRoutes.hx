package ccc.compute.server.execution.routes;

import t9.js.jsonrpc.Routes;

import promhx.Promise;
import ccc.TypedDynamicObject;
import js.npm.bluebird.Bluebird;

#if ((nodejs && !macro) && !excludeccc)
	import ccc.compute.server.cwl.CWLTools;
#end

/**
 * This is the HTTP RPC/API contact point to the compute queue.
 */
class RpcRoutes
{
	@rpc({
		alias:'test-jobs',
		doc:'Get all running test jobs'
	})
	public function getTestJobsIds() :Promise<Array<JobId>>
	{
#if ((nodejs && !macro) && !excludeccc)
		return _injector.getValue(ServiceMonitorRequest).getAllRunningTestJobs();
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'cwl',
		doc:'Run all server functional tests'
	})
	public function workflowRun(git :String, sha :String, cwl :String, input :String, ?inputs :DynamicAccess<String>) :Promise<JobResult>
	{
#if ((nodejs && !macro) && !excludeccc)
		return CWLTools.workflowRun(_docker, this, git, sha, cwl, input, inputs);
#else
		return Promise.promise(null);
#end
	}

// 	@rpc({
// 		alias:'cwl-test',
// 		doc:'Test running a CWL workflow'
// 	})
// 	public function testWorkflow() :Promise<Bool>
// 	{
// #if ((nodejs && !macro) && !excludeccc)
// 		return CWLTools.testWorkflow(_injector);
// #else
// 		return Promise.promise(null);
// #end
// 	}

	@rpc({
		alias:'log',
		doc:'Set the log level'
	})
	public function logLevel(?level :Null<Int>) :Promise<Int>
	{
#if ((nodejs && !macro) && !excludeccc)
		if (level != null) {
			level = Std.parseInt(level + '');
			Log.warn('Setting log level=$level');
			Logger.GLOBAL_LOG_LEVEL = level;
		}
		return Promise.promise(Logger.GLOBAL_LOG_LEVEL);
#else
		return Promise.promise(1);
#end
	}

	@rpc({
		alias:'status',
		doc:'Get the running status of the system: pending jobs, running jobs, worker machines'
	})
	public function status() :Promise<SystemStatus>
	{
#if ((nodejs && !macro) && !excludeccc)
		return ServerCommands.status();
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'info',
		doc:'Get the running status of this worker only'
	})
	public function info() :Promise<SystemStatus>
	{
#if ((nodejs && !macro) && !excludeccc)
		return ServerCommands.status();
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'serverversion',
		doc:'Get the server version info'
	})
	public function serverVersion() :Promise<ServerVersionBlob>
	{
#if ((nodejs && !macro) && !excludeccc)
		return Promise.promise(ServerCommands.version());
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias: 'jobv2',
		doc: 'Commands to query jobs, e.g. status, outputs.',
		args: {
			'command': {'doc':'Command to run in the docker container [remove | kill | result | status | exitcode | stats | definition | time]'},
			'jobId': {'doc': 'Job Id(s)'}
		},
		docCustom:'   With no jobId arguments, all jobs are returned.\n   commands:\n      remove\n      kill\n      result\n      status\t\torder of job status: [pending,copying_inputs,copying_image,container_running,copying_outputs,copying_logs,finalizing,finished]\n      exitcode\n      stats\n      definition\n      time'
	})
	public function doJobCommand_v2(command :JobCLICommand, jobId :JobId) :Promise<Dynamic>
	{
#if ((nodejs && !macro) && !excludeccc)
		return JobCommands.doJobCommand(_injector, jobId, command);
#else
		return Promise.promise(null);
#end
	}

@rpc({
		alias: 'job',
		doc: 'Commands to query jobs, e.g. status, outputs.',
		args: {
			'command': {'doc':'Command to run in the docker container [remove | kill | result | status | exitcode | stats | definition | time]'},
			'jobId': {'doc': 'Job Id(s)'},
			'json': {'doc': 'Output is JSON instead of human readable [true]'},
		},
		docCustom:'   With no jobId arguments, all jobs are returned.\n   commands:\n      remove\n      kill\n      result\n      status\t\torder of job status: [pending,copying_inputs,copying_image,container_running,copying_outputs,copying_logs,finalizing,finished]\n      exitcode\n      stats\n      definition\n      time'
	})
	public function doJobCommand(command :JobCLICommand, jobId :Array<JobId>, ?json :Bool = true) :Promise<TypedDynamicObject<JobId,Dynamic>>
	{
#if ((nodejs && !macro) && !excludeccc)
		if (command == null) {
			return PromiseTools.error('Missing command.');
		}
		return __doJobCommandInternal(command, jobId, json);
#else
		return Promise.promise(null);
#end
	}

	function __doJobCommandInternal(command :JobCLICommand, jobId :Array<JobId>, ?json :Bool = false) :Promise<TypedDynamicObject<JobId,Dynamic>>
	{
#if ((nodejs && !macro) && !excludeccc)
		switch(command) {
			case Remove,RemoveComplete,Kill,Status,Result,ExitCode,Definition,JobStats,Time:
			default:
				return Promise.promise(cast {error:'Unrecognized job subcommand=\'$command\' [remove | kill | result | status | exitcode | stats | definition | time]'});
		}

		var jobIds = jobId;//Better name

		function getResultForJob(job) :Promise<Dynamic> {
			return switch(command) {
				case Remove:
					JobCommands.removeJob(_injector, job);
				case RemoveComplete:
					JobCommands.deleteJobFiles(_injector, job)
						.pipe(function(_) {
							return JobCommands.removeJob(_injector, job);
						});
				case Kill:
					JobCommands.killJob(_injector, job);
				case Status:
					JobCommands.getStatusv1(_injector, job);
				case Result:
					JobCommands.getJobResults(_injector, job);
				case ExitCode:
					JobCommands.getExitCode(_injector, job);
				case JobStats:
					JobCommands.getJobStats(_injector, job)
						.then(function(stats) {
							return stats != null ? stats.toJson() : null;
						});
				case Time:
					JobCommands.getJobStats(_injector, job)
						.then(function(stats) {
							if (stats != null) {
								return stats != null ? stats.toJson() : null;
								var enqueueTime = stats.enqueueTime;
								var finishTime = stats.finishTime;
								var result = {
									start: stats.enqueueTime,
									duration: stats.isFinished() ? stats.finishTime - stats.enqueueTime : null
								}
								return result;
							} else {
								return null;
							}
						});
				case Definition:
					JobCommands.getJobDefinition(_injector, job);
			}
		}

		return Promise.whenAll(jobIds.map(getResultForJob))
			.then(function(results :Array<Dynamic>) {
				var result :TypedDynamicObject<JobId,Dynamic> = {};
				for(i in 0...jobIds.length) {
					Reflect.setField(result, jobIds[i], results[i]);
				}
				return result;
			});
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias: 'jobs',
		doc: 'List all job ids'
	})
	public function jobs() :Promise<Array<JobId>>
	{
#if ((nodejs && !macro) && !excludeccc)
		return JobCommands.getAllJobs(_injector);
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'deleteAllJobs',
		doc:'Deletes all jobs'
	})
	@:keep
	public function deleteAllJobs()
	{
#if ((nodejs && !macro) && !excludeccc)
		return JobCommands.deleteAllJobs(_injector);
#else
		return Promise.promise(true);
#end
	}

	@rpc({
		alias:'job-stats',
		doc:'Get job stats'
	})
	@:keep
	public function jobStats(jobId :JobId, ?raw :Bool = false) :Promise<Dynamic>
	{
#if ((nodejs && !macro) && !excludeccc)
		return JobCommands.getJobStats(_injector, jobId, raw);
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'jobs-pending-delete',
		doc:'Deletes all pending jobs'
	})
	@:keep
	public function deletePending() :Promise<DynamicAccess<String>>
	{
#if ((nodejs && !macro) && !excludeccc)
		return JobCommands.deletingPending(_injector);
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'job-wait',
		doc:'Waits until a job has finished before returning'
	})
	public function getJobResult(jobId :JobId, ?timeout :Float = 86400000) :Promise<JobResult>
	{
#if ((nodejs && !macro) && !excludeccc)
		return JobCommands.getJobResult(_injector, jobId, timeout);
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'pending',
		doc:'Get pending jobs'
	})
	public function pending() :Promise<Array<JobId>>
	{
#if ((nodejs && !macro) && !excludeccc)
		return JobCommands.pending();
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'worker-remove',
		doc:'Removes a worker'
	})
	public function workerRemove(id :MachineId) :Promise<String>
	{
#if ((nodejs && !macro) && !excludeccc)
		Assert.notNull(id);
		return Promise.promise("FAILED NOT IMPLEMENTED YET");
		// return ccc.compute.server.InstancePool.workerFailed(_redis, id);
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'status-workers',
		doc:'Get detailed status of all workers'
	})
	public function statusWorkers() :Promise<Dynamic>
	{
#if ((nodejs && !macro) && !excludeccc)
		// return WorkerCommands.statusWorkers(_redis);
		return Promise.promise(null);
#else
		return Promise.promise(null);
#end
	}

// 	@rpc({
// 		alias:'reset',
// 		doc:'Resets the server: kills and removes all jobs, removes local and remote data on jobs in the database.'
// 	})
// 	public function serverReset() :Promise<Bool>
// 	{
// #if ((nodejs && !macro) && !excludeccc)
// 		return ServerCommands.serverReset(_redis, _fs);
// #else
// 		return Promise.promise(null);
// #end
// 	}

	@rpc({
		alias:'remove-all-workers-and-jobs',
		doc:'Removes a worker'
	})
	public function removeAllJobsAndWorkers() :Promise<Bool>
	{
#if ((nodejs && !macro) && !excludeccc)
		Log.warn('remove-all-workers-and-jobs');
		return Promise.promise(true)
			.pipe(function(_) {
				return deleteAllJobs();
			})
			
			// .pipe(function(_) {
			// 	return _workerProvider.setMinWorkerCount(0);
			// })
			// .pipe(function(_) {
			// 	return _workerProvider.setMaxWorkerCount(0);
			// })
			.thenTrue()
			// .pipe(function(_) {
			// 	Log.warn('Removing all workers');
			// 	return _workerProvider.shutdownAllWorkers();
			// })
			;
#else
		return Promise.promise(false);
#end
	}

	@rpc({
		alias:'runturbo',
		doc:'Run docker job(s) on the compute provider. Example:\n cloudcannon run --image=elyase/staticpython --command=\'["python", "-c", "print(\'Hello World!\')"]\'',
		args:{
			'command': {'doc':'Command to run in the docker container. E.g. --command=\'["echo", "foo"]\''},
			'image': {'doc': 'Docker image name [busybox].'},
			'imagePullOptions': {'doc': 'Docker image pull options, e.g. auth credentials'},
			'inputs': {'doc': 'Object hash of inputs.'},
			'workingDir': {'doc': 'The current working directory for the process in the docker container.'},
			'cpus': {'doc': 'Minimum number of CPUs required for this process.'},
			'maxDuration': {'doc': 'Maximum time (in seconds) this job will be allowed to run before being terminated.'},
			'meta': {'doc': 'Metadata logged and saved with the job description and results.json'}
		}
	})
	public function submitTurboJob(
		?image :String,
#if ((nodejs && !macro) && !excludeccc)
		?imagePullOptions :PullImageOptions,
#else
		?imagePullOptions :Dynamic,
#end
		?command :Array<String>,
		?inputs :Dynamic<String>,
		?workingDir :String,
		?cpus :Int = 1,
		?maxDuration :Int = 600,
		?inputsPath :String,
		?outputsPath :String,
		?meta :Dynamic
		) :Promise<JobResultsTurbo>
	{
		var request :BatchProcessRequestTurbo = {
			image: image,
			imagePullOptions: imagePullOptions,
			command: command,
			inputs: inputs,
			workingDir: workingDir,
			parameters: {cpus: cpus, maxDuration:maxDuration},
			inputsPath: inputsPath,
			outputsPath: outputsPath,
			meta: meta
		}

#if ((nodejs && !macro) && !excludeccc)
		return submitTurboJobJson(request);
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'runturbojson',
		doc:'Run docker job(s) on the compute provider. Example:\n cloudcannon run --image=elyase/staticpython --command=\'["python", "-c", "print(\'Hello World!\')"]\'',
		args:{
			'job': {'doc':'BatchProcessRequestTurbo'}
		}
	})
	public function submitTurboJobJson(job :BatchProcessRequestTurbo) :Promise<JobResultsTurbo>
	{
#if ((nodejs && !macro) && !excludeccc)

		//Convert between the old and the new
		var newJob :BatchProcessRequestTurboV2 = cast Reflect.copy(job);
		newJob.inputs = [];
		if (job.inputs != null) {
			for (inputField in Reflect.fields(job.inputs)) {
				var val = Reflect.field(job.inputs, inputField);
				newJob.inputs.push({
					name: inputField,
					type: InputSource.InputInline,//Default
					value: val
				});
			}
		}

		//Convert between the new and the old
		return submitTurboJobJsonV2(newJob)
			.then(function(result) {
				var prevResultVersion :JobResultsTurbo = cast Reflect.copy(result);
				prevResultVersion.outputs = {};
				if (result.outputs != null) {
					for (output in result.outputs) {
						var stringValue = if (output.encoding != null) {
							Buffer.from(output.value, output.encoding).toString('utf8');
						} else {
							output.value;
						}
						Reflect.setField(prevResultVersion.outputs, output.name, stringValue);
					}
				}
				return prevResultVersion;
			});
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'runturbojsonv2',
		doc:'Run docker job(s) on the compute provider. Example:\n cloudcannon run --image=elyase/staticpython --command=\'["python", "-c", "print(\'Hello World!\')"]\'',
		args:{
			'job': {'doc':'BatchProcessRequestTurboV2'}
		}
	})
	public function submitTurboJobJsonV2(job :BatchProcessRequestTurboV2) :Promise<JobResultsTurboV2>
	{
#if ((nodejs && !macro) && !excludeccc)
		return ServiceBatchComputeTools.runTurboJobRequestV2(_injector, job);
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'submitjob',
		doc:'Run docker job(s) on the compute provider. Example:\n cloudcannon run --image=elyase/staticpython --command=\'["python", "-c", "print(\'Hello World!\')"]\'',
		args:{
			'command': {'doc':'Command to run in the docker container. E.g. --command=\'["echo", "foo"]\''},
			'image': {'doc': 'Docker image name [busybox].'},
			'pull_options': {'doc': 'Docker image pull options, e.g. auth credentials'},
			'inputs': {'doc': 'Array of input source objects {type:[url|inline(default)], name:<filename>, value:<string>, encoding:[utf8(default)|base64|ascii|hex]} See https://nodejs.org/api/buffer.html for more info about supported encodings.'},
			'workingDir': {'doc': 'The current working directory for the process in the docker container.'},
			'cpus': {'doc': 'Minimum number of CPUs required for this process.'},
			'maxDuration': {'doc': 'Maximum time (in seconds) this job will be allowed to run before being terminated.'},
			'resultsPath': {'doc': 'Custom path on the storage service for the generated job.json, stdout, and stderr files.'},
			'inputsPath': {'doc': 'Custom path on the storage service for the inputs files.'},
			'outputsPath': {'doc': 'Custom path on the storage service for the outputs files.'},
			'wait': {'doc': 'Do not return request until compute job is finished. Only use for short jobs.'},
			'meta': {'doc': 'Metadata logged and saved with the job description and results.json'}
		}
	})
	public function submitJob(
		?image :String,
#if ((nodejs && !macro) && !excludeccc)
		?pull_options :PullImageOptions,
#else
		?pull_options :Dynamic,
#end
		?command :Array<String>,
		?inputs :Array<ComputeInputSource>,
		?workingDir :String,
		?cpus :Int = 1,
		?maxDuration :Int = 600,
		?resultsPath :String,
		?inputsPath :String,
		?outputsPath :String,
		?containerInputsMountPath :String,
		?containerOutputsMountPath :String,
		?wait :Bool = false,
		?meta :Dynamic
		) :Promise<JobResult>
	{
		var request :BasicBatchProcessRequest = {
			image: image,
			pull_options: pull_options,
			cmd: command,
			inputs: inputs,
			workingDir: workingDir,
			parameters: {cpus: cpus, maxDuration:maxDuration},
			resultsPath: resultsPath,
			inputsPath: inputsPath,
			outputsPath: outputsPath,
			containerInputsMountPath: containerInputsMountPath,
			containerOutputsMountPath: containerOutputsMountPath,
			wait: wait,
			meta: meta
		}

#if ((nodejs && !macro) && !excludeccc)
		return ServiceBatchComputeTools.runComputeJobRequest(_injector, request);
#else
		return Promise.promise(null);
#end
	}

	@rpc({
		alias:'submitJobJson',
		doc:'Submit a job as a JSON object',
		args:{
			'job': {'doc':'BasicBatchProcessRequest'}
		}
	})
	public function submitJobJson(job :BasicBatchProcessRequest) :Promise<JobResult>
	{
#if ((nodejs && !macro) && !excludeccc)
		return ServiceBatchComputeTools.runComputeJobRequest(_injector, job);
#else
		return Promise.promise(null);
#end
	}

#if ((nodejs && !macro) && !excludeccc)
	@inject public var _injector :minject.Injector;
	@inject public var _context :t9.remoting.jsonrpc.Context;
	@inject public var _docker :Docker;

	public function new() {}

	@post
	public function postInject()
	{
		_context.registerService(this);
	}

	public function multiFormJobSubmissionRouter() :js.node.http.IncomingMessage->js.node.http.ServerResponse->(?Dynamic->Void)->Void
	{
		return function(req, res, next) {
			var contentType :String = req.headers['content-type'];
			var isMultiPart = contentType != null && contentType.indexOf('multipart/form-data') > -1;
			if (isMultiPart) {
				ServiceBatchComputeTools.handleMultiformBatchComputeRequest(_injector, req, res, next);
			} else {
				next();
			}
		}
	}

	function returnHelp() :String
	{
		return 'help';
	}

	public function dispose() {}

	public static function init(injector :Injector)
	{
		//Ensure there is only a single jsonrpc Context object
		if (!injector.hasMapping(t9.remoting.jsonrpc.Context)) {
			injector.map(t9.remoting.jsonrpc.Context).toValue(new t9.remoting.jsonrpc.Context());
		}

		//Create all the services, and map the RPC methods to the context object
		if (!injector.hasMapping(RpcRoutes)) {
			var rpcRoutes = new RpcRoutes();
			injector.map(RpcRoutes).toValue(rpcRoutes);
			injector.injectInto(rpcRoutes);
		}

		// if (!injector.hasMapping(ServiceTests)) {
		// 	var serviceTests = new ServiceTests();
		// 	injector.map(ServiceTests).toValue(serviceTests);
		// 	injector.injectInto(serviceTests);
		// }
	}

	public static function router(injector :Injector) :js.npm.express.Router
	{
		init(injector);

		var context :t9.remoting.jsonrpc.Context = injector.getValue(t9.remoting.jsonrpc.Context);

		var router = js.npm.express.Express.GetRouter();
		/* /rpc */
		//Handle the special multi-part requests. These are a special case.
		router.post(SERVER_API_RPC_URL_FRAGMENT, injector.getValue(RpcRoutes).multiFormJobSubmissionRouter());

		var timeout = 1000*60*30;//30m
		router.post(SERVER_API_RPC_URL_FRAGMENT, Routes.generatePostRequestHandler(context, timeout));
		router.get(SERVER_API_RPC_URL_FRAGMENT + '*', Routes.generateGetRequestHandler(context, SERVER_API_RPC_URL_FRAGMENT, timeout));

		return router;
	}

	public static function routerVersioned(injector :Injector) :js.npm.express.Router
	{
		init(injector);

		var context :t9.remoting.jsonrpc.Context = injector.getValue(t9.remoting.jsonrpc.Context);

		var router = js.npm.express.Express.GetRouter();
		var routerVersioned = js.npm.express.Express.GetRouter();

		switch(CCCVersion.v1) {
			case v1:
			case none:
			//This expression will trigger a compilation fail if we add more versions
		}
		var version = Type.enumConstructor(CCCVersion.v1);
		//Handle the special multi-part requests. These are a special case.
		router.post('/${version}', injector.getValue(RpcRoutes).multiFormJobSubmissionRouter());

		//Show all methods
		router.get('/${version}', function(req, res) {
			res.json({methods:context.methodDefinitions()});
		});

		router.use('/${version}', routerVersioned);

		js.npm.JsonRpcExpressTools.addExpressRoutes(routerVersioned, context);

		var timeout = 1000*60*30;//30m
		router.post('/${version}', Routes.generatePostRequestHandler(context, timeout));
		router.get('/$version/*', Routes.generateGetRequestHandler(context, version, timeout));

		router.get('/fork/test', function(req, res, next) {
			res.send('ok /fork/test');
		});

		return router;
	}
#end
}