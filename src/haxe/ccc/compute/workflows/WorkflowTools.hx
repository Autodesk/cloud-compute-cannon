package ccc.compute.workflows;

import ccc.storage.ServiceStorage;

import js.node.Fs;
import js.node.Path;
import js.node.stream.Readable;
import js.npm.fsextended.FsExtended;

import promhx.StreamPromises;

import util.streams.StreamTools;

using promhx.PromiseTools;

class WorkflowTools
{
	public static function getWorkflowPath(workflowId :String) :String
	{
		return 'workflow/${workflowId}';
	}

	public static function getWorkflowResultPath(workflowId :String) :String
	{
		return 'workflow/${workflowId}/${WORKFLOW_RESULT_JSON_FILE}';
	}

	public static function isFinishedWorkflow(fs :ServiceStorage, workflowId :String) :Promise<Bool>
	{
		return fs.exists(getWorkflowResultPath(workflowId));
	}

	public static function saveWorkflowResult(fs :ServiceStorage, workflowId :String, result :WorkflowResult) :Promise<Bool>
	{
		var data = Json.stringify(result, null, "  ");
		return fs.writeFile(getWorkflowResultPath(workflowId), StreamTools.stringToStream(data));
	}

	public static function getWorkflowResult(fs :ServiceStorage, workflowId :String) :Promise<WorkflowResult>
	{
		return fs.readFile(getWorkflowResultPath(workflowId))
			.pipe(function(stream) {
				return StreamPromises.streamToString(stream);
			})
			.then(function(s) {
				return Json.parse(s);
			});
	}

	public static function getWorkflowHash(inputFilePaths :String) :Promise<Dynamic>
	{
		var promise = new DeferredPromise();
		var hash :Dynamic->String = Node.require('object-hash');
		FsExtended.listFiles(inputFilePaths, {recursive:true}, function(err, files) {
			if (err != null) {
				promise.boundPromise.reject(err);
				return;
			}
			files.remove(WORKFLOW_JSON_FILE);
			files.sort(Reflect.compare);

			getFileHash(Path.join(inputFilePaths, WORKFLOW_JSON_FILE))
				.pipe(function(md5) {
					// md5s.push(md5);
					return Promise.whenAll(files.map(function(f) {
						var path = Path.join(inputFilePaths, f);
						return getFileHash(path);
					}))
					.then(function(hashes) {
						hashes.push(md5);
						return hashes;
					});
				})
				.then(function(hashes) {
					promise.resolve(hash(hashes));
				})
				.catchError(function(err) {
					promise.boundPromise.reject(err);
				});
		});

		return promise.boundPromise;
	}

	public static function runWorkflow(workflowId :WorkflowId, storage :ServiceStorage, workflow :WorkflowDefinition, inputFilePaths :String, ?removeJobs :Bool = true) :Promise<Dynamic>
	{
		var finalPromises :Array<Promise<JobResult>> = [];
		var pipes = new Map<WorkflowPipe, Promise<JobResult>>();
		var allResults :Array<JobResult> = [];


		//Get input pipes
		if (workflow.pipes == null) {
			return PromiseTools.error("WorkflowTools.runWorkflow workflow.pipes = null");
		}

		function findNextPipe(beginPipe :WorkflowPipe) {
			var next = null;
			for (pipe in workflow.pipes) {
				if (pipe == beginPipe) {
					continue;
				}
				if (pipe.source.transform != null && pipe.source.transform == beginPipe.target.transform) {
					next = pipe;
					break;
				}
			}
			if (next != null) {
				if (pipes[next] == null) {
					//Connect the promises
					var previousPromise = pipes[beginPipe];
					var nextPromise = previousPromise
						.pipe(function(jobResult :JobResult) {
							if (jobResult.error != null) {
								return Promise.promise(jobResult);
							}
							if (jobResult.exitCode != 0) {
								throw {message:'Previous job failed', previousJobResult:jobResult};
							}
							var actualOutputs = jobResult.outputs;
							var sourceOutput = next.source.output;
							if (!actualOutputs.has(sourceOutput)) {
								throw 'Missing required output actualOutputs=${actualOutputs} sourceOutput=$sourceOutput';
							}
							var targetInputName = next.target.input;
							var outputUrl = jobResult.outputsBaseUrl + sourceOutput;
							var inputUrls :DynamicAccess<String> = {};
							inputUrls[targetInputName] = outputUrl;
							return runWorkflowJob(workflow.transforms[next.target.transform], inputUrls, null)
								.then(function(jobResult) {
									allResults.push(jobResult);
									return jobResult;
								});
						});
					pipes[next] = nextPromise;
				}
			}
			return next;
		}

		function findFinalPromise(beginPipe :WorkflowPipe) {
			var final = beginPipe;
			while(findNextPipe(final) != null) {
				final = findNextPipe(final);
			}

			if (!finalPromises.has(pipes[final])) {
				finalPromises.push(pipes[final]);
			}
		}

		try {
			//Create all the input pipes, then find the final output pipe
			for (pipe in workflow.pipes) {
				if (pipe.source.file != null) {
					var thisPipe = pipe;
					//This is an input
					var inputFileName = pipe.source.file;
					var transform = workflow.transforms.get(pipe.target.transform);
					if (transform == null) {
						throw 'Missing target transform=${pipe.target}';
					}
					var inputStreams :DynamicAccess<IReadable> = {};
					var readStream = null;
					var inputPath = Path.join(inputFilePaths, inputFileName);
					readStream = Fs.createReadStream(inputPath);
					inputStreams.set(pipe.target.input, readStream);
					var promise = runWorkflowJob(transform, null, inputStreams);
					promise.then(function(jobResult) {
						allResults.push(jobResult);
						return jobResult;
					}).catchError(function(err) {});
					pipes.set(pipe, promise);
					findFinalPromise(pipe);
				}
			}
		} catch(err :Dynamic) {
			return PromiseTools.error(err);
		}

		var pipeResults = {};
		for (pipe in pipes.keys()) {
			var thisPipe = pipe;
			pipes.get(pipe).then(function(result) {
				Reflect.setField(thisPipe, 'result', result);
			});
		}

		return Promise.whenAll(finalPromises)
			.pipe(function(allFinalResults) {

				var promises = [];
				var output :DynamicAccess<String> = {};
				var finalResult = {
					output: output,
					error: null,
					pipes: workflow.pipes
				}
				var isError = allFinalResults.exists(function(jobResult) {
					return jobResult.error != null;
				});
				if (isError) {
					var error = allFinalResults.find(function(jobResult) {
						return jobResult.error != null;
					});
					finalResult.error = error;
				} else {
					var basePath = getWorkflowPath(workflowId);
					promises = allFinalResults.map(function(jobResult) {
						var sourceUrl = jobResult.outputsBaseUrl + jobResult.outputs[0];
						var targetUrl = Path.join(basePath, 'result', jobResult.outputs[0]);
						return storage.copyFile(sourceUrl, targetUrl)
							.then(function(_) {
								finalResult.output.set(jobResult.outputs[0], storage.getExternalUrl(targetUrl));
								return true;
							});
					});
				}

				var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.ServiceBatchCompute, true)
					.setConnection(new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(SERVER_LOCAL_RPC_URL));
				var jobIds = allResults.map(function(jobResult) return jobResult.jobId).array();
				return Promise.whenAll(promises)
					.then(function(_) {
						traceCyan('Deleting workflow jobs=$jobIds');
						proxy.doJobCommand(JobCLICommand.RemoveComplete, jobIds)
							.then(function(_) {
								Log.info('Removed workflow=$workflowId jobs=$jobIds');
							})
							.catchError(function(err) {
								Log.error('Error deleting workflow jobs=$jobIds error=$err');
							});
						return finalResult;
					});
			});
	}

	public static function runWorkflowJob(transform :WorkflowTransform, inputUrls :DynamicAccess<String>, inputStreams :DynamicAccess<IReadable>) :Promise<JobResult>
	{
		var forms :DynamicAccess<Dynamic> = {};
		var inputsArray = [];
		if (inputUrls != null) {
			for (key in inputUrls.keys()) {
				var inputUrl :ComputeInputSource = {
					type: InputSource.InputUrl,
					value: inputUrls[key],
					name: key
				}
				inputsArray.push(inputUrl);
			}
		}
		if (inputStreams != null) {
			for (key in inputStreams.keys()) {
				forms[key] = inputStreams[key];
			}
		}

		var request: BasicBatchProcessRequest = {
			inputs: inputsArray,
			image: transform.image,
			cmd: transform.command,
			wait: true
		}

		return ccc.compute.client.ClientTools.postJob(SERVER_LOCAL_HOST, request, forms)
			.errorPipe(function(err) {
				return Promise.promise(cast {
					error: err,
					request: request,
					transform: transform,
					inputUrls: inputUrls,
					inputStreams: inputStreams.keys()
				});
			});
	}

	public static function getFileHash(filePath :String) :Promise<String>
	{
		var hash :Dynamic->String = Node.require('object-hash');
		var promise = new DeferredPromise();
		var options = if (filePath.endsWith('.json')) {
			{encoding:'utf8'};
		} else {
			{};
		}
		FsExtended.readFile(filePath, options, function(err, buffer) {
			if (err != null) {
				promise.boundPromise.reject(err);
				return;
			}
			if (filePath.endsWith('.json')) {
				try {
					var obj = Json.parse(cast buffer);
					promise.resolve(hash(obj));
				} catch(parseErr :Dynamic) {
					traceRed(parseErr);
					promise.resolve(hash(buffer));
				}
			} else {
				promise.resolve(hash(buffer));
			}
		});
		return promise.boundPromise;
	}
}