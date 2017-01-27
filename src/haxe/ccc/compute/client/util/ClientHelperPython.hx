package ccc.compute.client.util;

import haxe.Json;
import haxe.remoting.JsonRpc;

import ccc.compute.client.externs.python.PythonRequests;

import python.*;
import python.lib.Builtins;
import python.lib.os.Path;

import sys.FileSystem;

import util.net.Host;

using ccc.compute.client.PyHelpers;

class ClientHelperPython
{
	static function main()
	{
		// var parameters :JobParams = {cpus:1, maxDuration:60*1000*10};

		// var request :BasicBatchProcessRequest = {
		// 	inputs: [],
		// 	image: 'elyase/staticpython',
		// 	cmd: ['python', '-c', 'print("Hello World!")'],
		// 	parameters: Lib.anonAsDict(parameters),
		// }

		// trace(run('http://localhost:9000', Lib.anonAsDict(request)));

		// trace(run('http://localhost:9000', 'elyase/staticpython', ['python', '-c', 'print("Hello World!")']));
		// trace(run('http://localhost:9000', 'elyase/staticpython', ['python', '-c', 'import os\nprint("/inputs=", os.path.listdir("/inputs"))'], null, ['README.md']));
		trace(run('http://localhost:9000', 'elyase/staticpython', ['python', '-c', 'import os\nprint("/inputs=", os.path.listdir("/inputs"))']));
	}

	/**
	 * [run description]
	 * @param  host         :String              [description]
	 * @param  ?image       :String              [description]
	 * @param  ?cmd         :Array<String>       [description]
	 * @param  ?workingDir  :String              [description]
	 * @param  ?cpus        :Int                 [description]
	 * @param  ?maxDuration :Int                 [description]
	 * @param  ?inputs      :Dict<String,String> [description]
	 * @param  ?inputFiles  :Array<String>       [description]
	 * @param  ?inputFolder :String              [description]
	 * @param  ?workingDir  :String              [description]
	 * @return              JobId of the job running, or throws an error
	 */
	public static function run(host :String,
		?image :String,
		?cmd :Array<String>,
		?inputs :Dict<String,String>,
		?inputFiles :Array<String>,
		?inputFolder :String,
		?workingDir :String,
		?cpus :Int = 1,
		?maxDuration :Int = 600000,
		?workingDir :String) :JobId
	{
		var jobParameters :JobParams = {cpus:cpus, maxDuration:maxDuration};
		var jobRequest :BasicBatchProcessRequest = {
			image: image,
			cmd: cmd,
			parameters: jobParameters,
			workingDir: workingDir,
			inputs: [],
		}

		var jobRequestDict = Lib.anonToDict(jobRequest);
		if (inputs != null) {
			var requestInputs :Array<Dynamic> = jobRequest.inputs;
			for (k in inputs.keys()) {
				var inputSource :ComputeInputSource = {
					type: InputSource.Inline,
					value: inputs.get(k),
					name: k,
					encoding: 'utf8'
				}
				requestInputs.push(Lib.anonToDict(inputSource));
			}
		}

		jobRequestDict.set('parameters', Lib.anonToDict(jobRequest.parameters));

		var paramsDict = new Dict();
		paramsDict.set('job', jobRequestDict);

		var jsonrpc :RequestDef = {
			jsonrpc: JsonRpcConstants.JSONRPC_VERSION_2,
			method: Constants.RPC_METHOD_JOB_SUBMIT,
			params: paramsDict,
			id: -1 //-1 means our client is not tracking ids.
		}

		var jsonrpcDict = Lib.anonToDict(jsonrpc);
		var jsonRpcString = python.lib.Json.dumps(jsonrpcDict);

		var url = host + Constants.SERVER_RPC_URL;

		var response = if (inputFiles != null || inputFolder != null) {
			var fileDict = new Dict<String,Dynamic>();
			fileDict.set(Constants.MULTIPART_JSONRPC_KEY, new Tuple<Dynamic>([Constants.MULTIPART_JSONRPC_KEY, jsonRpcString]));
			if (inputFiles != null) {
				for (fileName in inputFiles) {
					var baseName = Path.basename(fileName);
					fileDict.set(baseName, new Tuple<Dynamic>([baseName, Builtins.open(fileName, 'rb'), 'application/octet-stream']));
				}
			}
			if (inputFolder != null) {
				if (FileSystem.isDirectory(inputFolder)) {
					var files = FileSystem.readDirectory(inputFolder);
					for (f in files) {
						fileDict.set(f, new Tuple<Dynamic>([f, Builtins.open(haxe.io.Path.join([inputFolder, f]), 'rb'), 'application/octet-stream']));
					}
				} else {
					throw 'Not a directory inputFolder=$inputFolder';
				}
			}
			PythonRequests.post.call(url, files=>fileDict);
		} else {
			var headers :KwArgs<Dynamic> = {'Content-Type': 'application/json-rpc'};
			PythonRequests.post.call(url, headers=>headers, data=>jsonRpcString);
		}
		var response = python.lib.Json.loads(response.text);

		if (response.hasKey('error') && response.get('error') != null) {
			throw response.get('error');
		} else {
			return response.get('result').get('jobId');
		}
	}

	public static function stdout(host :String, jobId :JobId) :String
	{
		//var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.ServiceBatchCompute);
		return '';
	}

	static function getProxy(host :Host)
	{
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.ServiceBatchCompute)
			.setConnection(new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(host));
		return proxy;
	}
}