package compute;

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