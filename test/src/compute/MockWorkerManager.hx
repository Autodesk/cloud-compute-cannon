package compute;

import ccc.compute.Definitions;
import ccc.compute.workers.WorkerManager;
import ccc.compute.workers.Worker;

class MockWorkerManager extends WorkerManager
{
	public function new()
	{
		super();
	}

	override function createWorker(workerDef :WorkerDefinition) :Worker
	{
		return new MockWorker(workerDef);
	}
}