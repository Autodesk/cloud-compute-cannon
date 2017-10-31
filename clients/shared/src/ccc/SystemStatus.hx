package ccc;

typedef SystemStatus = {
	var pendingTop5 :Array<JobId>;
	var pendingCount :Int;
	var workers :Array<{id :MachineId, jobs:Array<{id:JobId,enqueued:String,started:String,duration:String}>,cpus:String}>;
	var finishedTop5 :TypedDynamicObject<JobFinishedStatus,Array<JobId>>;
	var finishedCount :Int;
}