package ccc.dashboard.state;

import ccc.WorkerState;

typedef WorkersState = {
	var workers :TypedDynamicAccess<MachineId, WorkerState>;
}