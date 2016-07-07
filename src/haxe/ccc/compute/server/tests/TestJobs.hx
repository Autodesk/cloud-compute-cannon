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

	public function XXtestWriteOutput() :Promise<Bool>
	{
		return Promise.promise(true);
		// var targetOut = 'out${Std.int(Math.random() * 100000000)}';
		// var targetOutFile = 'out${Std.int(Math.random() * 100000000)}';
		// var proxy = ServerTestTools.getProxy(_serverHostRPCAPI);
		// return proxy.submitJob('busybox', ["echo", targetOut, ">", targetOutFile])
		// 	.pipe(function(out) {
		// 		return ClientCompute.getJobResult(_serverHost, out.jobId);
		// 	})
		// 	.pipe(function(jobResult) {
		// 		var stdOutUrl = jobResult.stdout;
		// 		assertNotNull(stdOutUrl);
		// 		return true;
		// 	});
	}

	public function new(targetHost :Host)
	{
		super(targetHost);
	}
}