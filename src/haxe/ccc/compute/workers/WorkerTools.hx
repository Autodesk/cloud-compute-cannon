package ccc.compute.workers;

import js.Node;
import js.npm.ssh2.Ssh;
import js.npm.RedisClient;
import js.npm.docker.Docker;

import promhx.CallbackPromise;
import promhx.Promise;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.deferred.DeferredStream;

import ccc.compute.InstancePool;
import ccc.storage.ServiceStorage;

import util.DockerTools;
import util.SshTools;

using promhx.PromiseTools;

typedef Instance = {
	function ssh() :Promise<SshClient>;
	function docker() :Docker;
}

class WorkerTools
{
	public static function getInstance(def :WorkerDefinition) :Instance
	{
		return {
			docker: function() {
				return new Docker(def.docker);
			},
			ssh: function() {
				return SshTools.getSsh(def.ssh);
			}
		};
	}

	public static function getDocker(ssh :ConnectOptions) :Docker
	{
		return new Docker({
			host: ssh.host,
			port: DOCKER_PORT,
			protocol: 'http'
		});
	}

	public static function filterWorkerByStatus(status :MachineStatus) :Worker->Bool
	{
		return function(worker :Worker) {
			return worker.computeStatus == status;
		}
	}

	public static function getWorker(redis :RedisClient, fs :ServiceStorage, id :MachineId) :Promise<Worker>
	{
		return InstancePool.getWorker(redis, id)
			.then(function(workerDef) {
				if (workerDef == null) {
					return null;
				} else {
					var injector = new minject.Injector();
					injector.map(js.npm.RedisClient).toValue(redis);
					injector.map(minject.Injector).toValue(injector);
					injector.map(ServiceStorage).toValue(fs);
					var worker = new Worker(workerDef);
					injector.injectInto(worker);
					return worker;
				}
			});
	}

	/**
	 * Delete docker images and local compute jobs directory
	 * @param  worker :WorkerDefinition [description]
	 * @return        [description]
	 */
	public static function cleanWorker(worker :InstanceDefinition) :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				if (worker.ssh != null) {
					return Promise.promise(true)
						.pipe(function(_) {
							//Stop and rm containers
							return SshTools.execute(worker.ssh, "docker stop $(docker ps -a -q) && docker rm --volumes $(docker ps -a -q)");
						})
						.pipe(function(_) {
							//Delete docker images
							return SshTools.execute(worker.ssh, "docker rmi -f $(docker images -q)");
						})
						.pipe(function(_) {
							//Delete docker volumes
							return SshTools.execute(worker.ssh, "docker volume rm $(docker volume ls -qf dangling=true)");
						})
						.pipe(function(_) {
							//Delete /computejobs files
							return SshTools.execute(worker.ssh, 'sudo rm -rf "$WORKER_JOB_DATA_DIRECTORY_WITHIN_CONTAINER/*"');
						})
						.thenTrue();
				} else {
					return Promise.promise(true);
				}
			});
	}

	public static function removeJobsOnMachine(docker :Docker, jobs :Array<ComputeJobId>) :Promise<Bool>
	{
		return Promise.promise(true);
	}

	/**
	 * Returns a Stream that returns a value. If the polling for the
	 * value fails, the stream is ended.
	 * @param  connection                   :Void->Bool   [description]
	 * @param  maxRetries                   :Int          [description]
	 * @param  doublingIntervalMilliseconds :Int          [description]
	 * @return                              [description]
	 */
	public static function pollValue<T>(connection :Void->Promise<T>, pollInterval :Int, maxRetries :Int, doublingRetryIntervalMilliseconds :Int) :Stream<T>
	{
		var stream = new promhx.deferred.DeferredStream();
		var ended = false;

		stream.boundStream.endThen(function(_) {
			ended = true;
		});

		var poll = null;
		poll = function() {
			if (ended) {
				return;
			}
			promhx.RetryPromise.pollDecayingInterval(connection, maxRetries, doublingRetryIntervalMilliseconds, 'WorkerTools.pollValue')
				.then(function(val) {
					if (!ended) {
						stream.resolve(val);
						haxe.Timer.delay(poll, pollInterval);
					}
				});
		}
		poll();

		return stream.boundStream;
	}
}