package ccc.compute.server.execution.routes;

import ccc.compute.server.execution.singleworker.ProcessQueue;
import ccc.storage.ServiceStorage;

import haxe.Json;
import haxe.remoting.JsonRpc;
import haxe.extern.EitherType;

import js.Node;
import js.node.stream.Readable;
import js.node.Http;
import js.node.http.*;
import js.npm.streamifier.Streamifier;
import js.npm.docker.Docker;
import js.npm.busboy.Busboy;
import js.npm.ssh2.Ssh;
import js.npm.RedisClient;
import js.npm.streamifier.Streamifier;

import minject.Injector;

import promhx.Promise;

import t9.js.jsonrpc.Routes;

import util.DockerRegistryTools;
import util.DockerTools;
import util.DockerUrl;
import util.RedisTools;
import util.streams.StdStreams;

class ServiceBatchComputeTools
{
	static var DEFAULT_JOB_PARAMS :JobParams = {cpus:1, maxDuration:600};//10 minutes

	public static function runComputeJobRequest(injector :Injector, job :BasicBatchProcessRequest) :Promise<JobResult>
	{
		if (job == null) {
			throw 'Null job argument in ServiceBatchCompute.run(...)';
		}

		var fs :ServiceStorage = injector.getValue(ServiceStorage);
		var processQueue :ProcessQueue = injector.getValue(ProcessQueue);
		var redis :RedisClient = injector.getValue(RedisClient);

		var jobStats :JobStats = redis;

		var jobId :JobId = null;
		var deleteInputs :Void->Promise<Bool> = null;
		var error :Dynamic = null;

		job.image = job.image == null ? Constants.DOCKER_IMAGE_DEFAULT : job.image;

		return Promise.promise(true)
			.pipe(function(_) {
				return ServiceBatchComputeTools.getNewJobId();
			})
			.pipe(function(id) {
				jobId = id;
				jobStats.requestRecieved(jobId);
				var dateString = Date.now().format("%Y-%m-%d");
				var inputs = null;
				var inputPath = job.inputsPath != null ? (job.inputsPath.endsWith('/') ? job.inputsPath : job.inputsPath + '/') : jobId.defaultInputDir();

				var parameters :JobParams = job.parameters == null ? ServiceBatchComputeTools.DEFAULT_JOB_PARAMS : job.parameters;
				var inputFilesObj = writeInputFiles(fs, job.inputs, inputPath);
				deleteInputs = inputFilesObj.cancel;
				var dockerJob :DockerJobDefinition = {
					jobId: jobId,
					image: {type:DockerImageSourceType.Image, value:job.image, pull_options:job.pull_options, optionsCreate:job.createOptions},
					command: job.cmd,
					inputs: inputFilesObj.inputs,
					workingDir: job.workingDir,
					inputsPath: job.inputsPath,
					outputsPath: job.outputsPath,
					resultsPath: job.resultsPath,
					containerInputsMountPath: job.containerInputsMountPath,
					containerOutputsMountPath: job.containerOutputsMountPath,
					parameters: parameters,
					meta: job.meta,
					appendStdOut: job.appendStdOut,
					appendStdErr: job.appendStdErr,
					mountApiServer: job.mountApiServer
				};

				Log.info({job_submission :dockerJob.jobId});
				Log.debug({job_submission :dockerJob});

				if (dockerJob.command != null && untyped __typeof__(dockerJob.command) == 'string') {
					throw 'command field must be an array, not a string';
				}
#if debug
				//Check the results path since we're not using UUID's anymore
				var resultsJsonPath = JobTools.resultJsonPath(dockerJob);
				return fs.exists(resultsJsonPath)
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
							parameters: parameters,
							priority: job.priority
						}
						processQueue.add(job);
						// return ComputeQueue.enqueue(_redis, job);
						return Promise.promise(true);
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
			.pipe(function(_) {
				if (error != null) {
					jobStats.jobFinished(jobId, Json.stringify(error));
					throw error;
				}
				if (job.wait == true) {
					// return getJobResult(jobId, job.parameters != null && job.parameters.maxDuration != null ? job.parameters.maxDuration : null);
					return JobCommands.getJobResult(injector, jobId);
				} else {
					var jobResult :JobResult = {jobId:jobId};
					return Promise.promise(jobResult);
				}
			});
	}

	public static function handleMultiformBatchComputeRequest(injector :Injector, req :js.node.http.IncomingMessage, res :js.node.http.ServerResponse, next :?Dynamic->Void) :Void
	{
		var fs :ServiceStorage = injector.getValue(ServiceStorage);
		var processQueue :ProcessQueue = injector.getValue(ProcessQueue);
		var redis :RedisClient = injector.getValue(RedisClient);

		var returned = false;
		var jsonrpc :RequestDefTyped<BasicBatchProcessRequest> = null;
		var promises = [];
		var jobId :JobId = null;
		var inputPath = null;
		var inputFileNames :Array<String> = [];

		var log = Log.log;

		var jobStats :JobStats = redis;

		function returnError(err :haxe.extern.EitherType<String, js.Error>, ?statusCode :Int = 500) {
			log.error('err=$err\njsonrpc=${jsonrpc == null ? "null" : Json.stringify(jsonrpc, null, "\t")}');
			if (returned) return;
			res.writeHead(statusCode, {'content-type': 'application/json'});
			res.end(Json.stringify({error: err}));
			returned = true;
			//Cleanup
			Promise.whenAll(promises)
				.then(function(_) {
					if (jsonrpc != null && jsonrpc.params != null && jsonrpc.params.inputsPath != null) {
						fs.deleteDir(jsonrpc.params.inputsPath)
							.then(function(_) {
								log.info('Got error, deleted job ${jsonrpc.params.inputsPath}');
							});
					} else {
						fs.deleteDir(jobId)
							.then(function(_) {
								log.info('Deleted job dir err=$err');
							});
					}
				});
		}

		function parseJsonRpc(val :String) {
			var fieldName = JsonRpcConstants.MULTIPART_JSONRPC_KEY;
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
					var inputFilesObj = writeInputFiles(fs, jsonrpc.params.inputs, inputPath);
					promises.push(inputFilesObj.promise.thenTrue());
					inputFilesObj.inputs.iter(inputFileNames.push);
				}
			} catch(err :Dynamic) {
				log.error(err);
				returnError('Failed to parse JSON, err=$err val=$val');
			}
		}

		getNewJobId()
			.then(function(newJobId) {
				jobId = newJobId;
				jobStats.requestRecieved(jobId);
				log = log.child({jobId:jobId});
				log.debug({message: 'Starting busboy compute request'});
				var tenGBInBytes = 10737418240;
				var busboy = new Busboy({headers:req.headers, limits:{fieldNameSize:500, fieldSize:tenGBInBytes}});
				var deferredFieldHandling = [];//If the fields come in out of order, we'll have to handle the non-JSON-RPC subsequently
				busboy.on(BusboyEvent.File, function(fieldName, stream, fileName, encoding, mimetype) {

					if (fieldName == JsonRpcConstants.MULTIPART_JSONRPC_KEY) {
						StreamPromises.streamToString(stream)
							.then(function(jsonrpcString) {
								parseJsonRpc(jsonrpcString);
							});
					} else {
						// if (inputPath == null) {
						// 	returnError('fieldName=$fieldName fileName=$fileName inputPath is null for a file input, meaning either there is no jsonrpc entry, or it has not finished loading, or the jsonrpc file is after this. The \'jsonrpc\' key must be first in the multipart request.', 400);
						// 	return;
						// }
						var attemptsMax = 8;
						var attempts = 0;
						function attempLoad() {
							if (inputPath == null) {
								attempts++;
								return false;
							}

							log.info('BusboyEvent.File writing input file $fieldName encoding=$encoding mimetype=$mimetype stream=${stream != null}');
							var inputFilePath = inputPath + fieldName;

							stream.on(ReadableEvent.Error, function(err) {
								log.error('Error in Busboy reading field=$fieldName fileName=$fileName mimetype=$mimetype error=$err');
							});
							stream.on('limit', function() {
								log.error('Limit event in Busboy reading field=$fieldName fileName=$fileName mimetype=$mimetype');
							});

							var fileWritePromise = fs.writeFile(inputFilePath, stream);
							fileWritePromise
								.then(function(_) {
									log.info('    finished writing input file $fieldName');
									return true;
								})
								.errorThen(function(err) {
									log.info('    error writing input file $fieldName err=$err');
									throw err;
									return true;
								});
							promises.push(fileWritePromise);
							inputFileNames.push(fieldName);
							return true;
						}

						var delay :Void->Void = null;
						delay = function() {
							attempts++;
							if (returned) {
								return;
							}
							if (attempts > attemptsMax) {
								returnError('fieldName=$fieldName fileName=$fileName inputPath is null for a file input, meaning either there is no jsonrpc entry, or it has not finished loading, or the jsonrpc file is after this. The \'jsonrpc\' key must be first in the multipart request.', 400);
							} else {
								Node.setTimeout(function() {
									if (!attempLoad()) {
										delay();
									}
								}, 100);
							}
						}

						if (!attempLoad()) {
							delay();
						}
					}
				});
				busboy.on(BusboyEvent.Field, function(fieldName, val, fieldnameTruncated, valTruncated) {
					if (returned) {
						return;
					}
					if (fieldName == JsonRpcConstants.MULTIPART_JSONRPC_KEY) {
						parseJsonRpc(val);
					} else {
						if (jsonrpc == null) {
							throw 'The "jsonrpc" multipart key must be the FIRST entry in the multipart request form';
						}
						var inputFilePath = (jsonrpc.params.inputsPath != null ? (jsonrpc.params.inputsPath.endsWith('/') ? jsonrpc.params.inputsPath : jsonrpc.params.inputsPath + '/') : jobId.defaultInputDir()) + fieldName;
						var fileWritePromise = fs.writeFile(inputFilePath, Streamifier.createReadStream(val));
						fileWritePromise
							.then(function(_) {
								log.info('    finished writing input file $fieldName');
								return true;
							})
							.errorThen(function(err) {
								log.info('    error writing input file $fieldName err=$err');
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
							jobStats.requestUploaded(jobId);

							var parameters :JobParams = jsonrpc.params.parameters == null ? DEFAULT_JOB_PARAMS : jsonrpc.params.parameters;
							var dockerJob :DockerJobDefinition = {
								jobId: jobId,
								image: {type:DockerImageSourceType.Image, value:jsonrpc.params.image, pull_options:jsonrpc.params.pull_options, optionsCreate:jsonrpc.params.createOptions},
								command: jsonrpc.params.cmd,
								inputs: inputFileNames,
								workingDir: jsonrpc.params.workingDir,
								inputsPath: jsonrpc.params.inputsPath,
								outputsPath: jsonrpc.params.outputsPath,
								containerInputsMountPath: jsonrpc.params.containerInputsMountPath,
								containerOutputsMountPath: jsonrpc.params.containerOutputsMountPath,
								resultsPath: jsonrpc.params.resultsPath,
								parameters: parameters,
								meta: jsonrpc.params.meta,
								appendStdOut: jsonrpc.params.appendStdOut,
								appendStdErr: jsonrpc.params.appendStdErr,
								mountApiServer: jsonrpc.params.mountApiServer
							};

							log.debug({job_submission :dockerJob});

							if (jsonrpc.params.cmd != null && untyped __typeof__(jsonrpc.params.cmd) == 'string') {
								throw 'command field must be an array, not a string';
							}

							var job :QueueJobDefinitionDocker = {
								id: jobId,
								item: dockerJob,
								parameters: parameters,
								priority: jsonrpc.params.priority == true
							}
							return Promise.promise(true)
								.pipe(function(_) {
									// return ComputeQueue.enqueue(_redis, job);
									log.info({log:"job submitted to queue"});
									processQueue.add(job);
									return Promise.promise(true);
								});
						})
						.then(function(_) {
							var maxDuration = jsonrpc.params.parameters != null && jsonrpc.params.parameters.maxDuration != null ? jsonrpc.params.parameters.maxDuration : null;
							JobCommands.returnJobResult(injector, res, jobId, jsonrpc.id, jsonrpc.params.wait, maxDuration);
						})
						.catchError(function(err) {
							jobStats.jobFinished(jobId, Json.stringify(err));
							log.error(err);
							returnError(err);
						});
				});
				busboy.on(BusboyEvent.PartsLimit, function() {
					log.error('BusboyEvent ${BusboyEvent.PartsLimit}');
				});
				busboy.on(BusboyEvent.FilesLimit, function() {
					log.error('BusboyEvent ${BusboyEvent.FilesLimit}');
				});
				busboy.on(BusboyEvent.FieldsLimit, function() {
					log.error('BusboyEvent ${BusboyEvent.FieldsLimit}');
				});
				busboy.on('error', function(err) {
					log.error('BusboyEvent error=' + Json.stringify(err));
					returnError(err);
				});
				req.pipe(busboy);
			});
	}

	public static function getNewJobId() :Promise<JobId>
	{
		return Promise.promise(JobTools.generateJobId());
	}

	/**
	 * Write inputs to the StorageService.
	 * @param  inputs     :Array<ComputeInputSource> [description]
	 * @param  inputsPath :String                    Path prefix to the input file.
	 * @return            A function that will cancel (delete) the written files if an error is triggered later.
	 */
	public static function writeInputFiles(fs :ServiceStorage, inputDescriptions :Array<ComputeInputSource>, inputsPath :String) :{cancel:Void->Promise<Bool>, inputs:Array<String>, promise:Promise<Dynamic>}
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
						if (input.value != null) {
							var buffer = new Buffer(input.value, encoding);
							promises.push(fs.writeFile(inputFilePath, Streamifier.createReadStream(buffer)));//{encoding:encoding}
							inputNames.push(input.name);
						}
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
							promises.push(fs.writeFile(inputFilePath, readable));
						} else {
							Log.warn({url:url});
							promises.push(
								fs.readFile(url)
									.pipe(function(stream) {
										return fs.writeFile(inputFilePath, stream);
									}));
						}
						inputNames.push(input.name);
					default:
						throw 'Unhandled input type="$type" from $inputDescriptions';
				}
			}
		}
		return {promise:Promise.whenAll(promises), inputs:inputNames, cancel:function() return fs.deleteDir(inputsPath)};
	}
}