package compute;

class TestWorkers extends TestComputeBase
{
	public function new() {}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				_workerManager = new WorkerManager();
				_injector.injectInto(manager);
			});
	}

	@timeout(500)
	public function testWorkerAddRemoveJobs()
	{
		var redis = getClient();

		var manager = _workerManager;

		var worker1 = WorkerProviderBoot2Docker.getLocalDockerWorker();
		worker1.id = 'testMachine1';
		var worker2 = WorkerProviderBoot2Docker.getLocalDockerWorker();
		worker2.id = 'testMachine2';

		var params;

		var poolId = 'testpool';

		return Promise.promise(true)
			.pipe(function(_) {
				return WorkerProviderTools.getWorkerParameters(worker1.docker)
					.then(function(v) {
						params = v;
						return true;
					});
			})

			.pipe(function(_) {
				return InstancePool.getAllWorkerIds(redis)
					.then(function(ids) {
						var val = assertEquals(ids.length, 0);
						return val;
					});
			})

			//Add the first machine
			.pipe(function(_) {
				return InstancePool.addInstance(redis, poolId, worker1, params)
					.thenWait(50)
					.then(function(_) {
						return assertEquals(manager.getWorkers().length, 1);
					});
			})

			//Add the second machine
			.pipe(function(_) {
				return InstancePool.addInstance(redis, poolId, worker2, params)
					.thenWait(50)
					.then(function(_) {
						return assertEquals(manager.getWorkers().length, 2);
					});
			})

			//Remove the first machine
			.pipe(function(_) {
				return InstancePool.removeInstance(redis, worker1.id)
					.thenWait(100)
					.then(function(_) {
						assertEquals(manager.getWorkers().length, 1);
						//But the machines marked as ready
						return assertEquals(manager.getWorkers().filter(WorkerTools.filterWorkerByStatus(MachineStatus.Idle)).length, 1);
					});
			})

			//Mark machine ready to remove
			.pipe(function(_) {
				return InstancePool.setInstanceStatus(redis, worker2.id, MachineStatus.WaitingForRemoval)
					.thenWait(50)
					.then(function(_) {
						assertNotNull(manager.getWorker(worker2.id));
						return assertEquals(manager.getWorker(worker2.id).computeStatus, MachineStatus.WaitingForRemoval);
					});
			})

			.thenTrue();

	}
}