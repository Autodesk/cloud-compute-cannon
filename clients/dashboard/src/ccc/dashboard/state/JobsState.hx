package ccc.dashboard.state;

typedef JobsState = {
	var all :TypedDynamicAccess<JobId, JobStatsData>;
	var active :Array<JobId>;
	var finished :Array<JobId>;
	// var finishedSet :TypedDynamicAccess<JobId, Bool>;
}