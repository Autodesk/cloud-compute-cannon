package compute;

class MockWorker extends Worker
{
	public function new(def :WorkerDefinition)
	{
		super(def);
	}

	override function startMonitor() {}
}