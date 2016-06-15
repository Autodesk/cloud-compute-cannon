package compute;

import ccc.compute.workers.Worker;

class MockWorker extends Worker
{
	public function new(def :WorkerDefinition)
	{
		super(def);
	}

	override function startPoll() {}
}