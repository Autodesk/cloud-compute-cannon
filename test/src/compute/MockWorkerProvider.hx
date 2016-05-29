package compute;

import promhx.Promise;

import ccc.compute.workers.WorkerProvider;
import ccc.compute.workers.WorkerProviderBase;
import ccc.compute.Definitions;
import ccc.compute.InstancePool;

import t9.abstracts.net.*;

using promhx.PromiseTools;
using Lambda;

/**
 * This doesn't actually do any 'workers', it just provides
 * access to the local boot2docker/docker system.
 */
class MockWorkerProvider extends WorkerProviderBase
{
	public static var CPUS_PER_WORKER = 2;
	public static var TIME_MS_WORKER_CREATION = 100;

	inline static var ID = 'mockprovider';

	static var MACHINE_ID_COUNTER = 1;

	public var _currentWorkers = Set.createString();

	public function new(?config :ServiceConfigurationWorkerProvider)
	{
		this.id = ID;
		if (config == null) {
			config = {
				type: ServiceWorkerProviderType.mock,
				minWorkers: 0,
				maxWorkers: 3,
				priority: 1,
				billingIncrement: 0
			};
		}
		super(config);
	}

	@post
	override public function postInjection() :Promise<Bool>
	{
		return super.postInjection()
			.pipe(function(_) {
				return setDefaultWorkerParameters({cpus:CPUS_PER_WORKER, memory:10000});
			});
	}

	override public function createWorker() :Promise<WorkerDefinition>
	{
		var promise = super.createWorker();
		if (promise != null) {
			// Log.info('createWorker using a deferred worker');
			return promise;
		} else {
			// Log.info('createWorker create a whole new instance');
			var machineId = 'mockMachine_' + (MACHINE_ID_COUNTER++);
			var worker = {
				id: machineId,
				hostPrivate: new HostName('fake'),
				hostPublic: new HostName('fake'),
				ssh: {
					host:'fakehost' + id,
					username: 'fakeusername'
				},
				docker: {
					host:'fakehost' + id,
					port: 0,
					protocol: 'http'
				}
			};
			_currentWorkers.add(worker.id);

			var workerParams :WorkerParameters = {
				cpus: Std.int(CPUS_PER_WORKER),
				memory: 0
			}
			return Promise.promise(true)
				.thenWait(TIME_MS_WORKER_CREATION)
				.pipe(function(_) {
					return InstancePool.addInstance(redis, this.id, worker, workerParams)
						.then(function(_) {
							return worker;
						});
				});
		}
	}

	override public function removeWorker(workerId :MachineId) :Promise<Bool>
	{
		_currentWorkers.remove(workerId);
		return super.removeWorker(workerId);
	}

	#if debug public #end
	override function verifyWorkerExists(workerId :MachineId) :Promise<Bool>
	{
		return Promise.promise(_currentWorkers.has(workerId) || getDeferredWorkerIds().has(workerId));
	}
}