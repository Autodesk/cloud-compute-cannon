package ccc.dashboard.action;

enum DashboardAction
{
	SetState(state :AppState);
	SetJobsState(jobsState :JobsState);
	SetJobState(jobState :JobState);
	SetActiveJobs(jobIds :Array<JobId>);
	// SetFinishedJobs(jobIds :Array<JobId>);
}
