package compute;

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
						error: jobError,
						copiedLogs: jobError == null
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

	override function checkMachine() :Promise<Bool>
	{
		return Promise.promise(true);
	}

	override public function removeJobFromDockerHost() :Promise<Bool>
	{
		return Promise.promise(true);
	}
}