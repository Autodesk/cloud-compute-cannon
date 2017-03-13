package ccc.compute.server.tests;

import ccc.compute.client.js.ClientJSTools;
import ccc.compute.server.tests.ServerTestTools.*;

import haxe.io.*;

import promhx.StreamPromises;
import promhx.RequestPromises;
import promhx.deferred.DeferredPromise;

class TestFailureConditions extends ServerAPITestBase
{
	public static var TEST_BASE = 'tests';

	@inject public var routes :ccc.compute.server.execution.routes.RpcRoutes;
	@inject public var redis :RedisClient;

	@timeout(240000)
	public function testTimeoutJob() :Promise<Bool>
	{
		var jobDurationSeconds = 60;
		var testBlob = createTestJobAndExpectedResults('testTimeoutJob', jobDurationSeconds);
		var expectedBlob = testBlob.expects;
		var jobRequest = testBlob.request;
		jobRequest.wait = false;
		jobRequest.priority = true;
		jobRequest.parameters = {maxDuration:2, cpus:1};

		var jobId :JobId = null;

		return ClientJSTools.postJob(_serverHost, jobRequest)
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				jobId = jobResult.jobId;
				return Promise.promise(true);
			})
			.thenWait(500)
			.pipe(function(_) {
				return routes.getJobResult(jobId);
			})
			.then(function(jobResult) {
				assertEquals(jobResult.status, JobFinishedStatus.TimeOut);
				return true;
			})
			.pipe(function(_) {
				var jobStatusTools :JobStateTools = redis;
				return jobStatusTools.getFinishedStatus(jobId)
					.then(function(status) {
						assertEquals(status, JobFinishedStatus.TimeOut);
						return true;
					});
			});
	}

	@timeout(240000)
	public function testJobCancelled() :Promise<Bool>
	{
		var jobDurationSeconds = 60;
		var testBlob = createTestJobAndExpectedResults('testCancelJob', jobDurationSeconds);
		var expectedBlob = testBlob.expects;
		var jobRequest = testBlob.request;
		jobRequest.wait = false;
		jobRequest.priority = true;
		jobRequest.parameters = {maxDuration:jobDurationSeconds, cpus:1};

		var jobId :JobId = null;

		return ClientJSTools.postJob(_serverHost, jobRequest)
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				jobId = jobResult.jobId;
				return Promise.promise(true);
			})
			.thenWait(10)
			.pipe(function(_) {
				return routes.doJobCommand(JobCLICommand.Kill, jobId);
			})
			.thenWait(10)
			.pipe(function(_) {
				return routes.doJobCommand(JobCLICommand.Result, jobId)
					.errorPipe(function(err) {
						return Promise.promise(null);
					});
			})
			.then(function(jobResult) {
				assertIsNull(jobResult);
				return true;
			});
	}

	public function new() { super(); }
}