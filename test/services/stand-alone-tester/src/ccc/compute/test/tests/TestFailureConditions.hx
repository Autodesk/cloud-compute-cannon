package ccc.compute.test.tests;

class TestFailureConditions extends ServerAPITestBase
{
	@timeout(240000)
	public function testTimeoutJob() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
		var jobDurationSeconds = 10;
		var testBlob = createTestJobAndExpectedResults('testTimeoutJob', jobDurationSeconds);
		var expectedBlob = testBlob.expects;
		var jobRequest = testBlob.request;
		jobRequest.wait = false;
		jobRequest.priority = true;
		jobRequest.parameters = {maxDuration:1, cpus:1};

		var jobId :JobId = null;

		return ClientJSTools.postJob(_serverHost, jobRequest)
			.pipe(function(jobResult :JobResultAbstract) {
				// js.Lib.debug();
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				jobId = jobResult.jobId;
				return Promise.promise(true);
			})
			.thenWait(1500)
			.pipe(function(_) {
				return routes.getJobResult(jobId);
			})
			.then(function(jobResult) {
				// js.Lib.debug();
				assertEquals(jobResult.status, JobFinishedStatus.TimeOut);
				return true;
			})
			.pipe(function(_) {
				return JobStateTools.getFinishedStatus(jobId)
					.then(function(status) {
						assertEquals(status, JobFinishedStatus.TimeOut);
						return true;
					});
			})
			//Asert the path to get the results is good
			.pipe(function(_) {
				var url = 'http://${_serverHost}/${jobRequest.resultsPath}/result.json';
				return RequestPromises.get(url, 100)
					.then(function(result) {
						assertTrue(true);
						return true;
					});
			});
	}

	@timeout(240000)
	public function testJobCancelled() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);
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
				return routes.doJobCommand_v2(JobCLICommand.Kill, jobId);
			})
			.thenWait(10)
			.pipe(function(_) {
				var f = function() { return routes.doJobCommand_v2(JobCLICommand.Result, jobId);};
				return RetryPromise.retryRegular(f, 16, 500);
			})
			.then(function(jobResult) {
				assertIsNull(jobResult);
				return true;
			})
			//Ensure that there is no storage trace
			.pipe(function(_) {
				var url = 'http://${_serverHost}/${jobRequest.resultsPath}/result.json';
				return RequestPromises.get(url, 100)
					.then(function(_) {
						assertTrue(false);
						return false;
					})
					.errorPipe(function(err) {
						return Promise.promise(true);
					});
			});
	}

	@timeout(60000)
	public function testJobFailedButStillRunsRestartsOnSameWorkerPrevJobCleanedUp() :Promise<Bool>
	{
		var routes = ProxyTools.getProxy(_serverHostRPCAPI);

		var docker = injector.getValue(Docker);

		if (docker == null) {
			traceYellow('testJobFailedButStillRunsRestartsOnSameWorkerPrevJobCleanedUp missing docker');
			return Promise.promise(true);
		}

		var jobDurationSeconds = 10;
		var testBlob = createTestJobAndExpectedResults('testJobFailedButStillRunsRestartsOnSameWorkerPrevJobCleanedUp', jobDurationSeconds);
		var expectedBlob = testBlob.expects;
		var jobRequest = testBlob.request;
		jobRequest.wait = false;
		jobRequest.priority = true;
		jobRequest.parameters = {maxDuration:jobDurationSeconds * 2, cpus:1};

		var jobId :JobId = null;

		return ClientJSTools.postJob(_serverHost, jobRequest)
			.pipe(function(jobResult :JobResultAbstract) {
				if (jobResult == null) {
					throw 'jobResult should not be null. Check the above section';
				}
				jobId = jobResult.jobId;
				return Promise.promise(true);
			})
			.pipe(function(_) {
				return JobStream.getStatusStream().waitUntilJobIsRunningInContainer(jobId, 1);
			})
			.pipe(function(containerId) {
				assertNotNull(containerId);
				var container = docker.getContainer(containerId);
				return DockerPromises.killContainer(container);
			})
			.pipe(function(_) {
				return JobStream.getStatusStream().waitUntilJobIsOnAttemptNumber(jobId, 2);
			})
			.pipe(function(_) {
				return JobStatsTools.get(jobId)
					.then(function(jobStats) {
						// traceYellow('jobStats=${Json.stringify(jobStats, null, "  ")}');
						assertTrue(jobStats.attempts.length > 1);
						return true;
					});
			})
			.pipe(function(_) {
				return JobStream.getStatusStream().waitUntilJobIsFinished(jobId);
			})
			.pipe(function(_) {
				return JobStatsTools.get(jobId)
					.then(function(jobStats) {
						assertEquals(jobStats.statusWorking, JobWorkingStatus.FinishedWorking);
						assertEquals(jobStats.status, JobStatus.Finished);
						assertEquals(jobStats.statusFinished, JobFinishedStatus.Success);
						assertTrue(jobStats.finished > 0);
						assertTrue(jobStats.attempts.length == 2);
						assertTrue(jobStats.attempts[1].worker != null);
						assertTrue(jobStats.attempts[1].copiedInputs > 0);
						// assertTrue(jobStats.attempts[1].copiedInputsAndImage > 0);
						assertTrue(jobStats.attempts[1].containerExited > 0);
						assertTrue(jobStats.attempts[1].enqueued > 0);
						assertTrue(jobStats.attempts[1].dequeued > 0);
						assertTrue(jobStats.attempts[1].copiedOutputs > 0);

						return true;
					});
			});
	}

	public function new() { super(); }
}