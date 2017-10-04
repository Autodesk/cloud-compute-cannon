package ccc.compute.test.tests;

import js.npm.shortid.ShortId;

typedef ExpectedResult = {
	var stdout :String;
	var stderr :String;
	var exitCode :Int;
	var outputs :DynamicAccess<String>;
}
class ServerTestTools
{
	public static function getServerAddress() :Host
	{
		var env = Sys.environment();
		if (env.exists('CCC')) {
			return env.get('CCC');
		} else {
			return new Host(new HostName('localhost'), new Port(SERVER_DEFAULT_PORT));
		}
	}

	public static function getProxy(?rpcUrl :UrlString)
	{
		rpcUrl = rpcUrl != null ? rpcUrl : UrlTools.rpcUrl(getServerAddress());
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.server.execution.routes.RpcRoutes, true)
			.setConnection(new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(rpcUrl));
		return proxy;
	}

	public static function getJobResult(jobId :JobId) :Promise<JobResult>
	{
		var rpcUrl = UrlTools.rpcUrl(getServerAddress());
		var proxy = getProxy(rpcUrl);
		function getJobData() {
			return cast proxy.doJobCommand_v2(JobCLICommand.Result, jobId);
		}
		return JobWebSocket.getJobResult(getServerAddress(), jobId, getJobData);
	}

	public static function createTestJobAndExpectedResults(testName :String, duration :Int, ?useCustomPaths :Bool = true) :{request:BasicBatchProcessRequest, expects:ExpectedResult}
	{
		var TEST_BASE = 'tests';

		var inputValueInline = 'in${ShortId.generate()}';
		var inputName1 = 'in${ShortId.generate()}';

		var outputName1 = 'out${ShortId.generate()}';
		var outputName2 = 'out${ShortId.generate()}';

		var outputValue1 = 'out${ShortId.generate()}';

		var inputInline :ComputeInputSource = {
			type: InputSource.InputInline,
			value: inputValueInline,
			name: inputName1
		}

		var random = ShortId.generate();
		var customInputsPath = '$TEST_BASE/$testName/$random/$DIRECTORY_INPUTS';
		var customOutputsPath = '$TEST_BASE/$testName/$random/$DIRECTORY_OUTPUTS';
		var customResultsPath = '$TEST_BASE/$testName/$random/results';

		if (!useCustomPaths) {
			customInputsPath = null;
			customOutputsPath = null;
			customResultsPath = null;
		}

		var outputValueStdout = 'out${ShortId.generate()}';
		var outputValueStderr = 'out${ShortId.generate()}';
		//Multiline stdout
		var script =
'#!/bin/sh
sleep ${duration}s
echo "$outputValueStdout"
echo "$outputValueStdout"
echo foo
echo "$outputValueStdout"
echo "$outputValueStderr" >> /dev/stderr
echo "$outputValue1" > /$DIRECTORY_OUTPUTS/$outputName1
cat /$DIRECTORY_INPUTS/$inputName1 > /$DIRECTORY_OUTPUTS/$outputName2
';

		var targetStdout = '$outputValueStdout\n$outputValueStdout\nfoo\n$outputValueStdout'.trim();
		var targetStderr = '$outputValueStderr';
		var scriptName = 'script.sh';
		var inputScript :ComputeInputSource = {
			type: InputSource.InputInline,
			value: script,
			name: scriptName
		}

		var inputsArray = [inputInline, inputScript];

		var request: BasicBatchProcessRequest = {
			inputs: inputsArray,
			image: DOCKER_IMAGE_DEFAULT,
			cmd: ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'],
			resultsPath: customResultsPath,
			inputsPath: customInputsPath,
			outputsPath: customOutputsPath,
			meta: {
				name: testName
			},
			wait: true
		}

		var expectedOutputs :DynamicAccess<String> = {};
		expectedOutputs[outputName1] = outputValue1;
		expectedOutputs[outputName2] = inputValueInline;

		var expectedResult :ExpectedResult = {
			stdout: '${outputValueStdout}\n${outputValueStdout}\nfoo\n${outputValueStdout}',
			stderr: '${outputValueStderr}',
			exitCode: 0,
			outputs: expectedOutputs
		}
		return {request:request, expects:expectedResult};
	}
}