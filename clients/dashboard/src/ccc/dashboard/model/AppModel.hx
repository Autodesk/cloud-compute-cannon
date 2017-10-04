package ccc.dashboard.model;

class AppModel
	implements IReducer<DashboardAction, AppState>
{
	public var initState :AppState = {
		workers: {workers:{}},
		jobs: {active:[], all:{}, finished:[]}
	};

	public var store :StoreMethods<ApplicationState>;

	public function new() {}

	/* SERVICE */

	public function reduce(state :AppState, action :DashboardAction) :AppState
	{
		return switch(action)
		{
			case SetState(newState):
				if (newState == null) {
					state;
				} else {
					newState;
				}
			case SetJobsState(newJobsState):
				// trace('newJobsState=${Reflect.fields(newJobsState)}');
				if (newJobsState == null) {
					state;
				} else {
					var newState :AppState = copy(state);
					// SetJobState can arrive first, if we do not check
					// previous job state versions this big update can
					// clobber the prior more recent version
					var prevJobsAll = state.jobs.all;
					// trace('prevJobsAll=${Json.stringify(prevJobsAll)}');
					newState.jobs = newJobsState;
					if (newState.jobs.all == null) {
						newState.jobs.all = {};
					}
					if (prevJobsAll != null) {
						for (jobId in prevJobsAll.keys()) {
							// trace('jobId=$jobId');
							if (newState.jobs.all.exists(jobId) && newState.jobs.all.get(jobId).v < prevJobsAll.get(jobId).v) {
								newState.jobs.all.set(jobId, prevJobsAll.get(jobId));
							}
						}
					}
					newState;
				}
			case SetJobState(newJobState):
				if (newJobState == null) {
					state;
				} else {
					if (state.jobs.all.exists(newJobState.jobId) && state.jobs.all.get(newJobState.jobId).v >= newJobState.v) {
						state;
					} else {
						var newState :AppState = copy(state);
						var newJobMap :TypedDynamicAccess<JobId, JobStatsData> = {};
						for (jobId in state.jobs.all.keys()) {
							newJobMap.set(jobId, state.jobs.all.get(jobId));
						}
						newJobMap.set(newJobState.jobId, newJobState);
						newState.jobs.all = newJobMap;
						newState;
					}
				}
			case SetActiveJobs(jobIds):
				if (jobIds == null) {
					jobIds = [];
				}
				if (jobIds.equalsDeep(state.jobs.active)) {
					state;
				} else {
					var newState :AppState = copy(state);
					newState.jobs.active = jobIds;
					var activeMap :TypedDynamicAccess<JobId, Bool> = {};
					for (id in newState.jobs.active) {
						activeMap.set(id, true);
					}
					newState.jobs.finished = state.jobs.all.keys().filter(function(id) {
						return !activeMap.exists(id);
					});
					newState;
				}
		}
	}
}
