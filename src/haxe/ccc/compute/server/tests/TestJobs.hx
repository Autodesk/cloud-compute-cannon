package ccc.compute.server.tests;

import util.DockerRegistryTools;

import promhx.RequestPromises;

class TestJobs extends ServerAPITestBase
{
	@timeout(120000)
	public function testWriteStdout() :Promise<Bool>
	{
		var targetOut = 'out${Std.int(Math.random() * 100000000)}';
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		return proxy.submitJob('busybox', ["echo", targetOut])
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var stdOutUrl = 'http://${SERVER_LOCAL_HOST}/${jobResult.stdout}';
				assertNotNull(stdOutUrl);
				return RequestPromises.get(stdOutUrl)
					.then(function(stdout) {
						stdout = stdout != null ? stdout.trim() : stdout;
						assertEquals(stdout, targetOut);
						return true;
					});
			});
	}

	@timeout(120000)
	public function testReadInput() :Promise<Bool>
	{
		var inputValue = 'in${Std.int(Math.random() * 100000000)}';
		var inputName = 'in${Std.int(Math.random() * 100000000)}';
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		var input :ComputeInputSource = {
			type: InputSource.InputInline,
			value: inputValue,
			name: inputName
		}
		return proxy.submitJob('busybox', ["cat", '/$DIRECTORY_INPUTS/$inputName'], [input])
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var stdOutUrl = 'http://${SERVER_LOCAL_HOST}/${jobResult.stdout}';
				assertNotNull(stdOutUrl);
				return RequestPromises.get(stdOutUrl)
					.then(function(stdout) {
						stdout = stdout != null ? stdout.trim() : stdout;
						assertEquals(stdout, inputValue);
						return true;
					});
			});
	}

	@timeout(120000)
	public function testWriteOutput() :Promise<Bool>
	{
		var outputValue = 'out${Std.int(Math.random() * 100000000)}';
		var outputName = 'out${Std.int(Math.random() * 100000000)}';
		var script =
'!/bin/sh
echo "$outputValue" > /$DIRECTORY_OUTPUTS/$outputName
';
		var scriptName = 'script.sh';
		var input :ComputeInputSource = {
			type: InputSource.InputInline,
			value: script,
			name: scriptName
		}
		var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		return proxy.submitJob('busybox', ["/bin/sh", '/$DIRECTORY_INPUTS/$scriptName'], [input])
			.pipe(function(out) {
				return ServerTestTools.getJobResult(out.jobId);
			})
			.pipe(function(jobResult) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				var outputUrl = jobResult.outputsBaseUrl;
				var outputs = jobResult.outputs != null ? jobResult.outputs : [];
				assertTrue(outputs.length == 1);
				var outputUrl = 'http://${SERVER_LOCAL_HOST}/${jobResult.outputsBaseUrl}/${outputs[0]}';
				return RequestPromises.get(outputUrl)
					.then(function(out) {
						out = out != null ? out.trim() : out;
						assertEquals(out, outputValue);
						return true;
					});
			});
	}

	public function new(targetHost :Host)
	{
		super(targetHost);
	}
}