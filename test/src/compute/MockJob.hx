package compute;

import ccc.compute.Definitions;
import ccc.compute.execution.Job;
import ccc.compute.execution.BatchComputeDocker;

import promhx.Promise;

import t9.abstracts.time.*;

using promhx.PromiseTools;

class MockJob extends Job
{
	public var jobDuration :Milliseconds = 0;
	public var jobOutputFiles :Array<String> = [];
	public var jobError :Dynamic = null;
	public var jobExitCode :Int = 0;
	public var workingStatus :JobWorkingStatus = JobWorkingStatus.FinishedWorking;

	public function new(computeId :ComputeJobId)
	{
		super(computeId);
	}

	override function executeJob() :ExecuteJobResult
	{
		var promise = Promise.promise(true)
			.then(function(_) {
				if (jobError != null) {
					throw jobError;
				}
				return true;
			})
			.thenWait(jobDuration)
			.then(function(_) {
				if (jobError == null) {
					var jobResult :BatchJobResult = {
						exitCode: jobExitCode,
						JobWorkingStatus: workingStatus,
						outputFiles: jobOutputFiles,
						error: jobError
					};
					return jobResult;
				} else {
					throw jobError;
				}
			});
		return {
			cancel:function() {},
			promise: promise
		}
	}

	override public function removeJobFromDockerHost() :Promise<Bool>
	{
		return Promise.promise(true);
	}
}