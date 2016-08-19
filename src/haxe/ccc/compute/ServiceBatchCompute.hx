package ccc.compute;

#if (nodejs && !macro)
	import haxe.remoting.JsonRpc;
	import t9.js.jsonrpc.Routes;

	import js.Node;
	import js.node.Buffer;
	import js.node.Path;
	import js.node.stream.Readable;
	import js.node.Http;
	import js.node.http.*;
	import js.npm.docker.Docker;
	import js.npm.busboy.Busboy;
	import js.npm.ssh2.Ssh;
	import js.npm.RedisClient;
	import js.npm.streamifier.Streamifier;

	import promhx.deferred.DeferredPromise;
	import promhx.RedisPromises;
	import promhx.StreamPromises;
	import promhx.PromiseTools;
	import promhx.DockerPromises;

	import ccc.compute.server.ServerCommands;
	import ccc.compute.server.ServerCommands.*;
	import ccc.compute.workers.WorkerProvider;
	import ccc.compute.InstancePool;

	import ccc.storage.ServiceStorage;
	import ccc.storage.StorageDefinition;
	import ccc.storage.StorageSourceType;
	import ccc.storage.StorageTools;

	import util.DockerTools;
	import util.DockerUrl;

	using Lambda;
	using StringTools;
	using ccc.compute.ComputeTools;
	using ccc.compute.ComputeQueue;
	using ccc.compute.JobTools;
	using promhx.PromiseTools;
	using DateTools;
#else
	typedef Express=Dynamic;
	typedef IncomingMessage=Dynamic;
	typedef ServerResponse=Dynamic;
#end

/**
 * This is the HTTP RPC/API contact point to the compute queue.
 */
class ServiceBatchCompute
{
	@rpc({
		alias:'nudge',
		doc:'Force the model to check pending jobs'
	})
	public function nudge() :Promise<ProcessResult>
	{
		return ComputeQueue.processPending(_redis);
	}

	@rpc({
		alias:'pending',
		doc:'Get pending jobs'
	})
	public function pending() :Promise<Array<JobId>>
	{
		return ServerCommands.pending(_redis);
	}

	@rpc({
		alias:'status',
		doc:'Get the running status of the system: pending jobs, running jobs, worker machines'
	})
	public function status() :Promise<SystemStatus>
	{
		return ServerCommands.status(_redis);
	}

	@rpc({
		alias:'serverversion',
		doc:'Get the server version info'
	})
	public function serverVersion() :Promise<ServerVersionBlob>
	{
		return Promise.promise(ServerCommands.version());
	}

	@rpc({
		alias:'reset',
		doc:'Resets the server: kills and removes all jobs, removes local and remote data on jobs in the database.'
	})
	public function serverReset() :Promise<Bool>
	{
		return ServerCommands.serverReset(_redis, _fs);
	}

	@rpc({
		alias:'worker-remove',
		doc:'Removes a worker'
	})
	public function workerRemove(id :MachineId) :Promise<Bool>
	{
		Assert.notNull(id);
		return ccc.compute.InstancePool.workerFailed(_redis, id);
	}

	@rpc({
		alias:'image-pull',
		doc:'Pulls a docker image and tags it into the local registry for workers to consume.',
		args:{
			tag: {doc: 'Custom tag for the image', short:'t'},
			opts: {doc: 'ADD ME', short:'o'}
		}
	})
	public function pullRemoteImageIntoRegistry(image :String, ?tag :String, ?opts: PullImageOptions) :Promise<DockerUrl>
	{
		return ServerCommands.pushImageIntoRegistry(image, tag, opts);
	}

	@rpc({
		alias:'submitjob',
		doc:'Run docker job(s) on the compute provider. Example:\n cloudcannon run --image=elyase/staticpython --command=\'["python", "-c", "print(\'Hello World!\')"]\'',
		args:{
			'command': {'doc':'Command to run in the docker container. E.g. --command=\'["echo", "foo"]\''},
			'image': {'doc': 'Docker image name [busybox].'},
			'inputs': {'doc': 'Array of input source objects {type:[url|inline(default)], name:<filename>, value:<string>, encoding:[utf8(default)|base64|ascii|hex]} See https://nodejs.org/api/buffer.html for more info about supported encodings.'},
			'workingDir': {'doc': 'The current working directory for the process in the docker container.'},
			'cpus': {'doc': 'Minimum number of CPUs required for this process.'},
			'maxDuration': {'doc': 'Maximum time (in seconds) this job will be allowed to run before being terminated.'},
			'resultsPath': {'doc': 'Custom path on the storage service for the generated job.json, stdout, and stderr files.'},
			'inputsPath': {'doc': 'Custom path on the storage service for the inputs files.'},
			'outputsPath': {'doc': 'Custom path on the storage service for the outputs files.'},
		}
	})
	public function submitJob(
		?image :String,
		?command :Array<String>,
		?inputs :Array<ComputeInputSource>,
		?workingDir :String,
		?cpus :Int = 1,
		?maxDuration :Int = 600000,
		?resultsPath :String,
		?inputsPath :String,
		?outputsPath :String
		) :Promise<{jobId:JobId}>
	{
		var request :BasicBatchProcessRequest = {
			image: image,
			cmd: command,
			inputs: inputs,
			workingDir: workingDir,
			parameters: {cpus: cpus, maxDuration:maxDuration},
			resultsPath: resultsPath,
			inputsPath: inputsPath,
			outputsPath: outputsPath,
		}

		return runComputeJobRequest(request);
	}

	@rpc({
		alias: 'jobs',
		doc: 'List all job ids'
	})
	public function jobs() :Promise<Array<JobId>>
	{
		return ComputeQueue.getAllJobIds(_redis);
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
		if (command == null) {
			return PromiseTools.error('Missing command.');
		}
		switch(command) {
			case Status:
				//The special case of the status of all jobs. Best to
				//do it all in one go instead of piecemeal.
				if (jobId == null || jobId.length == 0) {
					return ComputeQueue.getJobStatuses(_redis)
						.then(function(jobStatusBlobs :TypedDynamicObject<JobId,JobStatusBlob>) {
							var result :TypedDynamicObject<JobId,String> = {};
							for (jobId in jobStatusBlobs.keys()) {
								var statusBlob :JobStatusBlob = jobStatusBlobs[jobId];
								var s :String = statusBlob.status == JobStatus.Working ? statusBlob.statusWorking : statusBlob.status;
								result[jobId] = s;
							}
							return result;
						})
						.errorPipe(function(err) {
							Log.error(err);
							return Promise.promise(null);
						});
				}
			default://continue
		}

		if (jobId == null || jobId.length == 0 || (jobId.length == 1 && jobId[0] == null)) {
			return ComputeQueue.getAllJobIds(_redis)
				.pipe(function(jobId) {
					return __doJobCommandInternal(command, jobId, json);
				});
		} else {
			var validJobPromises = jobId.map(function(j) return ComputeQueue.isJob(_redis, j));
			var invalidJobIds = [];
			return Promise.whenAll(validJobPromises)
				.pipe(function(jobChecks) {
					var validJobIds = [];
					for (i in 0...jobId.length) {
						var jid = jobId[i];
						if (jobChecks[i]) {
							validJobIds.push(jid);
						} else {
							invalidJobIds.push(jid);
						}
					}
					return __doJobCommandInternal(command, validJobIds, json);
				})
				.then(function(results) {
					for (invalidJobId in invalidJobIds) {
						Reflect.setField(results, invalidJobId, RESULT_INVALID_JOB_ID);
					}
					return results;
				});
		}
	}

	function __doJobCommandInternal(command :JobCLICommand, jobId :Array<JobId>, ?json :Bool = false) :Promise<TypedDynamicObject<JobId,Dynamic>>
	{
#if (nodejs && !macro)
		switch(command) {
			case Remove,RemoveComplete,Kill,Status,Result,ExitCode,Definition,JobStats,Time:
			default:
				return Promise.promise(cast {error:'Unrecognized job subcommand=\'$command\' [remove | kill | result | status | exitcode | stats | definition | time]'});
		}

		var jobIds = jobId;//Better name

		function getResultForJob(job) :Promise<Dynamic> {
			return switch(command) {
				case Remove:
					ComputeQueue.removeJob(_redis, job);
				case RemoveComplete:
					removeJobComplete(_redis, _fs, job);
				case Kill:
					killJob(_redis, job);
				case Status:
					getStatus(_redis, job);
				case Result:
					getJobResults(_redis, _fs, job);
				case ExitCode:
					getExitCode(_redis, _fs, job);
				case JobStats:
					getJobStats(_redis, job)
						.then(function(stats) {
							return stats != null ? stats.toJson() : null;
						});
				case Time:
					getJobStats(_redis, job)
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
					getJobDefinition(_redis, _fs, job);
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


#if (nodejs && !macro)
	@inject public var _fs :ServiceStorage;
	@inject public var _redis :RedisClient;
	@inject public var _config :StorageDefinition;
	@inject public var _storage :ServiceStorage;
	@inject public var _injector :minject.Injector;

	public function new() {}

	public function multiFormJobSubmissionRouter() :IncomingMessage->ServerResponse->(?Dynamic->Void)->Void
	{
		return function(req, res, next) {
			var contentType :String = req.headers['content-type'];
			var isMultiPart = contentType != null && contentType.indexOf('multipart/form-data') > -1;
			if (isMultiPart) {
				handleMultiformBatchComputeRequest(req, res, next);
			} else {
				next();
			}
		}
	}

	public function router() :js.node.express.Router
	{
		var router = js.node.express.Express.GetRouter();

		/* /rpc */
		//Handle the special multi-part requests. These are a special case.
		router.post(SERVER_API_RPC_URL_FRAGMENT, multiFormJobSubmissionRouter());

		var serverContext = new t9.remoting.jsonrpc.Context();
		serverContext.registerService(this);
		//Remote tests
		var serviceTests = new ccc.compute.server.tests.ServiceTests();
		_injector.injectInto(serviceTests);
		serverContext.registerService(serviceTests);
		serverContext.registerService(ccc.compute.server.ServerCommands);
		router.post(SERVER_API_RPC_URL_FRAGMENT, Routes.generatePostRequestHandler(serverContext));
		router.get(SERVER_API_RPC_URL_FRAGMENT + '*', Routes.generateGetRequestHandler(serverContext, SERVER_API_RPC_URL_FRAGMENT));

		router.post('/build/*', buildDockerImageRouter);
		return router;
	}

	function buildDockerImageRouter(req :IncomingMessage, res :ServerResponse, next :?Dynamic->Void) :Void
	{
		function returnError(err :String, ?statusCode :Int = 400) {
			res.setHeader("content-type","application/json-rpc");
			res.writeHead(statusCode);
			res.end(Json.stringify({
				error: err
			}));
		}

		var repositoryString :String = untyped req.params[0];

		if (repositoryString == null) {
			returnError('You must supply a docker repository after ".../build/"', 400);
			return;
		}

		var repository :DockerUrl = repositoryString;

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
		ServerCommands.buildImageIntoRegistry(req, repository, res)
			.then(function(imageUrl) {
				js.Node.setTimeout(function() {
					res.writeHead(200);
					res.end(imageUrl);
				}, 5000);
			})
			.catchError(function(err) {
				returnError('Failed to build image err=$err', 500);
			});
	}

	function runComputeJobRequest(job :BasicBatchProcessRequest) :Promise<{jobId:JobId}>
	{
		if (job == null) {
			throw 'Null job argument in ServiceBatchCompute.run(...)';
		}
		var jobId :JobId = null;
		var deleteInputs :Void->Promise<Bool> = null;

		job.image = job.image == null ? Constants.DOCKER_IMAGE_DEFAULT : job.image;

		var error :Dynamic = null;
		return Promise.promise(true)
			.pipe(function(_) {
				return getNewJobId();
			})
			.pipe(function(id) {
				jobId = id;
				var dateString = Date.now().format("%Y-%m-%d");
				var inputs = null;
				var inputPath = job.inputsPath != null ? (job.inputsPath.endsWith('/') ? job.inputsPath : job.inputsPath + '/') : jobId.defaultInputDir();

				var inputFilesObj = writeInputFiles(job.inputs, inputPath);
				deleteInputs = inputFilesObj.cancel;
				var dockerJob :DockerJobDefinition = {
					jobId: jobId,
					image: {type:DockerImageSourceType.Image, value:job.image},
					command: job.cmd,
					inputs: inputFilesObj.inputs,
					workingDir: job.workingDir,
					inputsPath: job.inputsPath,
					outputsPath: job.outputsPath,
					resultsPath: job.resultsPath
				};

				if (dockerJob.command != null && untyped __typeof__(dockerJob.command) == 'string') {
					throw 'command field must be an array, not a string';
				}
#if debug
				//Check the results path since we're not using UUID's anymore
				var resultsJsonPath = JobTools.resultJsonPath(dockerJob);
				return _fs.exists(resultsJsonPath)
					.then(function(exists) {
						if (exists) {
							throw 'jobId=$jobId results.json already exists at $resultsJsonPath';
						}
						return true;
					})
#else
				return Promise.promise(true)
#end
					.pipe(function(_) {
						return inputFilesObj.promise;
					})
					.pipe(function(result) {
						var job :QueueJobDefinitionDocker = {
							id: jobId,
							item: dockerJob,
							parameters: job.parameters == null ? {cpus:1, maxDuration:2 * 60000} : job.parameters,
						}
						return ComputeQueue.enqueue(_redis, job);
					})
					.thenTrue();
			})
			//It has this odd errorPipe (then maybe throw later) promise
			//structure because otherwise the caught and rethrown error
			//won't actually be passed down the promise chain
			.errorPipe(function(err) {
				Log.error('Got error, deleting inputs for jobId=$jobId err=$err');
				error = err;
				if (deleteInputs != null) {
					var deletePromise = deleteInputs();
					if (deletePromise != null) {
						deletePromise.then(function(_) {
							Log.error('Deleted inputs for jobId=$jobId err=$err');
						});
					}
				}
				return Promise.promise(true);
			})
			.then(function(_) {
				if (error != null) {
					throw error;
				}
				return {jobId:jobId};
			});
	}

	function returnHelp() :String
	{
		return 'help';
	}

	public function handleMultiformBatchComputeRequest(req :IncomingMessage, res :ServerResponse, next :?Dynamic->Void) :Void
	{
		getNewJobId()
			.then(function(jobId) {
				var jsonrpc :RequestDefTyped<BasicBatchProcessRequest> = null;
				var promises = [];
				var returned = false;
				// var inputs = new Array<ComputeInputSource>();
				function returnError(err :haxe.extern.EitherType<String, js.Error>) {
					Log.error('err=$err\njsonrpc=${jsonrpc == null ? "null" : Json.stringify(jsonrpc, null, "\t")}');
					if (returned) return;
					res.writeHead(500, {'content-type': 'application/json'});
					res.end(Json.stringify({error: err}));
					returned = true;
					//Cleanup
					Promise.whenAll(promises)
						.then(function(_) {
							if (jsonrpc != null && jsonrpc.params != null && jsonrpc.params.inputsPath != null) {
								_fs.deleteDir(jsonrpc.params.inputsPath)
									.then(function(_) {
										Log.info('Got error, deleted job ${jsonrpc.params.inputsPath}');
									});
							} else {
								_fs.deleteDir(jobId)
									.then(function(_) {
										Log.info('Deleted job dir err=$err');
									});
							}
						});
				}

				var inputFileNames :Array<String> = [];
				var tenGBInBytes = 10737418240;
				var busboy = new Busboy({headers:req.headers, limits:{fieldNameSize:500, fieldSize:tenGBInBytes}});
				var inputPath = null;
				var deferredFieldHandling = [];//If the fields come in out of order, we'll have to handle the non-JSON-RPC subsequently
				busboy.on(BusboyEvent.File, function(fieldName, stream, fileName, encoding, mimetype) {
					Log.info('BusboyEvent.File writing input file $fieldName encoding=$encoding mimetype=$mimetype stream=${stream != null}');
					var inputFilePath = inputPath + fieldName;

					stream.on(ReadableEvent.Error, function(err) {
						Log.error('Error in Busboy reading field=$fieldName fileName=$fileName mimetype=$mimetype error=$err');
					});
					stream.on('limit', function() {
						Log.error('Limit event in Busboy reading field=$fieldName fileName=$fileName mimetype=$mimetype');
					});

					var fileWritePromise = _fs.writeFile(inputFilePath, stream);
					fileWritePromise
						.then(function(_) {
							Log.info('    finished writing input file $fieldName');
							return true;
						})
						.errorThen(function(err) {
							Log.info('    error writing input file $fieldName err=$err');
							throw err;
							return true;
						});
					promises.push(fileWritePromise);
					inputFileNames.push(fieldName);
				});
				busboy.on(BusboyEvent.Field, function(fieldName, val, fieldnameTruncated, valTruncated) {
					if (returned) {
						return;
					}
					if (fieldName == JsonRpcConstants.MULTIPART_JSONRPC_KEY) {
						try {
							try {
								jsonrpc = Json.parse(val);
							} catch (err :Dynamic) {
								//Try URL-decoding
								val = StringTools.urlDecode(val);
								jsonrpc = Json.parse(val);
							}
							if (jsonrpc.method == null || jsonrpc.method != Constants.RPC_METHOD_JOB_SUBMIT) {
								returnError('JsonRpc method ${Constants.RPC_METHOD_JOB_SUBMIT} != ${jsonrpc.method}');
								return;
							}
							if (jsonrpc.method == null || jsonrpc.method != Constants.RPC_METHOD_JOB_SUBMIT) {
								returnError('JsonRpc method ${Constants.RPC_METHOD_JOB_SUBMIT} != ${jsonrpc.method}');
								return;
							}

							inputPath = jsonrpc.params.inputsPath != null ? (jsonrpc.params.inputsPath.endsWith('/') ? jsonrpc.params.inputsPath : jsonrpc.params.inputsPath + '/') : jobId.defaultInputDir();
							if (jsonrpc.params.inputs != null) {
								var inputFilesObj = writeInputFiles(jsonrpc.params.inputs, inputPath);
								promises.push(inputFilesObj.promise.thenTrue());
								inputFilesObj.inputs.iter(inputFileNames.push);
							}
						} catch(err :Dynamic) {
							Log.error(err);
							returnError('Failed to parse JSON, err=$err val=$val');
						}
					} else {
						var inputFilePath = (jsonrpc.params.inputsPath != null ? (jsonrpc.params.inputsPath.endsWith('/') ? jsonrpc.params.inputsPath : jsonrpc.params.inputsPath + '/') : jobId.defaultInputDir()) + fieldName;
						var fileWritePromise = _fs.writeFile(inputFilePath, Streamifier.createReadStream(val));
						fileWritePromise
							.then(function(_) {
								Log.info('    finished writing input file $fieldName');
								return true;
							})
							.errorThen(function(err) {
								Log.info('    error writing input file $fieldName err=$err');
								throw err;
								return true;
							});
						promises.push(fileWritePromise);
						inputFileNames.push(fieldName);
					}
				});

				busboy.on(BusboyEvent.Finish, function() {
					if (returned) {
						return;
					}
					Promise.promise(true)
						.pipe(function(_) {
							return Promise.whenAll(promises);
						})
						.pipe(function(_) {

							var dockerJob :DockerJobDefinition = {
								jobId: jobId,
								image: {type:DockerImageSourceType.Image, value:jsonrpc.params.image},
								command: jsonrpc.params.cmd,
								inputs: inputFileNames,
								workingDir: jsonrpc.params.workingDir,
								inputsPath: jsonrpc.params.inputsPath,
								outputsPath: jsonrpc.params.outputsPath,
								resultsPath: jsonrpc.params.resultsPath
							};

							if (jsonrpc.params.cmd != null && untyped __typeof__(jsonrpc.params.cmd) == 'string') {
								throw 'command field must be an array, not a string';
							}

							var job :QueueJobDefinitionDocker = {
								id: jobId,
								item: dockerJob,
								parameters: jsonrpc.params.parameters == null ? {cpus:1, maxDuration:2 * 60000} : jsonrpc.params.parameters,
							}
							return Promise.promise(true)
								// .pipe(function(_) {
								// 	var dockerUrl :DockerUrl = dockerJob.image.value;
								// 	trace('ORIGINAL URL=$dockerUrl');
								// 	return ServiceBatchComputeTools.checkRegistryForDockerUrl(dockerUrl)
								// 		.then(function(url) {
								// 			trace('FINAL URL=$url');
								// 			dockerJob.image.value = url;
								// 			return true;
								// 		});
								// })
								.pipe(function(_) {
									return ComputeQueue.enqueue(_redis, job);
								});
						})
						.then(function(_) {
							res.writeHead(200, {'content-type': 'application/json'});
							var jsonRpcRsponse = {
								result: {jobId:jobId},
								jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2,
								id: jsonrpc.id
							}
							res.end(Json.stringify(jsonRpcRsponse));
						})
						.catchError(function(err) {
							Log.error(err);
							returnError(err);
						});
				});
				busboy.on(BusboyEvent.PartsLimit, function() {
					Log.error('BusboyEvent ${BusboyEvent.PartsLimit}');
				});
				busboy.on(BusboyEvent.FilesLimit, function() {
					Log.error('BusboyEvent ${BusboyEvent.FilesLimit}');
				});
				busboy.on(BusboyEvent.FieldsLimit, function() {
					Log.error('BusboyEvent ${BusboyEvent.FieldsLimit}');
				});
				req.pipe(busboy);
			});
	}

	public function getNewJobId() :Promise<JobId>
	{
		return Promise.promise(JobTools.generateJobId());
		// return ComputeQueue.generateJobId(_redis);
	}

	/**
	 * Write inputs to the StorageService.
	 * @param  inputs     :Array<ComputeInputSource> [description]
	 * @param  inputsPath :String                    Path prefix to the input file.
	 * @return            A function that will cancel (delete) the written files if an error is triggered later.
	 */
	function writeInputFiles(inputDescriptions :Array<ComputeInputSource>, inputsPath :String) :{cancel:Void->Promise<Bool>, inputs:Array<String>, promise:Promise<Dynamic>}
	{
		var promises = [];
		var inputNames = [];
		if (inputDescriptions != null) {
			for (input in inputDescriptions) {
				var inputFilePath = Path.join(inputsPath, input.name);
				var type :InputSource = input.type == null ? InputSource.InputInline : input.type;
				var encoding :InputEncoding = input.encoding == null ? InputEncoding.utf8 : input.encoding;
				switch(encoding) {
					case utf8,base64,ascii,utf16le,ucs2,binary,hex:
					default: throw 'Unsupported input encoding=$encoding';
				}
				switch(type) {
					case InputInline:
						var buffer = new Buffer(input.value, encoding);
						promises.push(_fs.writeFile(inputFilePath, Streamifier.createReadStream(buffer)));//{encoding:encoding}
						inputNames.push(input.name);
					case InputUrl:
						if (input.value == null) {
							throw 'input.value is null for $input';
						}
						var url :String = input.value;
						if (url.startsWith('http')) {
							var request :String->IReadable = Node.require('request');
							//Fuck the request library
							//https://github.com/request/request/issues/887
							var readable :js.node.stream.Duplex<Dynamic> = untyped __js__('new require("stream").PassThrough()');
							request(input.value).pipe(readable);
							promises.push(_fs.writeFile(inputFilePath, readable));
						} else {
							promises.push(
								_fs.readFile(url)
									.pipe(function(stream) {
										return _fs.writeFile(inputFilePath, stream);
									}));
						}
						inputNames.push(input.name);
					default:
						throw 'Unhandled input type="$type" from $inputDescriptions';
				}
			}
		}
		return {promise:Promise.whenAll(promises), inputs:inputNames, cancel:function() return _fs.deleteDir(inputsPath)};
	}

	static function verifyJobCommand(command :String)
	{
		if (command != null && !command.startsWith('[')) {
			throw 'command must be a parsable JSON Array of strings e.g. \'["echo", "foo"]\'';
		}
	}

	static function buildImageInRegistry(docker :Docker, registry :String, stream :IReadable, imageName :String) :Promise<String>
	{
		var repo = registry + '/' + imageName + ':latest';
		return DockerTools.buildDockerImage(docker, repo, stream, null)
			.pipe(function(_) {//Built, now send to registry
				return DockerTools.pushImage(docker, repo);
			})
			.then(function(_) {
				return repo;
			});
	}

	public function dispose() {}
#end
}