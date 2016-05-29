package compute;

import ccc.compute.Definitions;
import ccc.compute.execution.Jobs;

import t9.abstracts.time.*;

using Lambda;

class MockJobs extends Jobs
{
	public var jobDuration :Milliseconds = 0;
	public var jobOutputFiles :Array<String> = [];
	public var jobError :Dynamic = null;
	public var jobExitCode :Int = 0;
	public var workingStatus :JobWorkingStatus = JobWorkingStatus.FinishedWorking;

	public function new() {super();}

	override function createJob(computeJobId :ComputeJobId)
	{
		var job = new MockJob(computeJobId);
		job.jobDuration = jobDuration;
		job.jobOutputFiles = jobOutputFiles.concat([]);
		job.jobError = jobError;
		job.jobExitCode = jobExitCode;
		job.workingStatus = workingStatus;
		return job;
	}

	public function getComputeJobIds() :Array<ComputeJobId>
	{
		var arr = [];
		for(id in _jobs.keys()) {
			arr.push(id);
		}
		return arr;
	}

	public function getJob(id :ComputeJobId) :MockJob
	{
		return cast _jobs.get(id);
	}
}
