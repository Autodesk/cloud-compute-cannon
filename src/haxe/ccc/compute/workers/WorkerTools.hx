package ccc.compute.workers;

import js.Node;
import js.npm.Ssh;
import js.npm.RedisClient;
import js.npm.Docker;

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

/**
 * Notes: the boot2docker machine needs to have sftp enabled:
 * Add
 * 	Subsystem sftp internal-sftp
 * to /var/lib/boot2docker/ssh/sshd_config
 *
 * This is meant to work, but I couldn't find the script (/etc/rc.d/sshd restart)
 * so I just restarted the damn machine.
 */
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
			port: 2375,
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
							return SshTools.execute(worker.ssh, 'sudo rm -rf $JOB_DATA_DIRECTORY_WITHIN_CONTAINER/*');
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

	public function createDockerPoll(docker :Docker, pollIntervalMilliseconds: Int, maxRetries:Int, doublingRetryIntervalMilliseconds: Int) :Stream<Bool>
	{
		return poll(
			function() {
				var promise = new CallbackPromise();
				docker.ping(promise.cb1);
				return promise;
			},
			pollIntervalMilliseconds,
			maxRetries,
			doublingRetryIntervalMilliseconds);
	}

	/**
	 * Returns a Stream that if a false value is returned, means that
	 * the connection failed (allowing for the configured retries).
	 * After a single failure (return of false), the Stream object is disposed.
	 * To dispose prior, call stream.end().
	 * @param  connection                   :Void->Bool   [description]
	 * @param  maxRetries                   :Int          [description]
	 * @param  doublingIntervalMilliseconds :Int          [description]
	 * @return                              [description]
	 */
	public static function poll(connection :Void->Promise<Dynamic>, pollInterval :Int, maxRetries :Int, doublingRetryIntervalMilliseconds :Int) :Stream<Bool>
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
			promhx.RetryPromise.pollDecayingInterval(connection, maxRetries, doublingRetryIntervalMilliseconds, 'WorkerTools.poll')
				.then(function(_) {
					if (!ended) {
						stream.resolve(true);
						haxe.Timer.delay(poll, pollInterval);
					}
				})
				.catchError(function(err) {
					if (!ended) {
						stream.resolve(false);
						stream.boundStream.end();
					}
				});
		}
		poll();

		return stream.boundStream;
	}
}