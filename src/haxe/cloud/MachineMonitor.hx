package cloud;

import js.npm.docker.Docker;
import js.npm.ssh2.Ssh;

import promhx.*;
import promhx.deferred.*;
import promhx.RetryPromise;

import util.DockerTools;
import util.SshTools;

enum StatusDocker {
	NotConfigured;
	Connecting;
	OK;
	ContactLost;
}

enum StatusDisk {
	NotConfigured;
	Connecting;
	OK;
	DiskSpaceExceeded;
}

enum MachineFailureType {
	DockerConnectionLost;
	DiskCapacityCritical;
}

enum MachineConnectionStatus {
	/* No connections or results of polls yet */
	Connecting;
	OK;
	/**
	 * Any failure implies a terminal failure, this
	 * machine should be destroyed. Once this staus
	 * is sent, the MachineMonitor is disposed
	 * since it is no longer listening, and should
	 * no longer be used.
	 */
	CriticalFailure(failureType :MachineFailureType);
}

class MachineMonitor
{
	public static function createDockerPoll(credentials :DockerConnectionOpts, pollType :PollType, pollIntervalMilliseconds: Int, maxRetries:Int, doublingRetryIntervalMilliseconds: Int) :Stream<Bool>
	{
		var docker = new Docker(credentials);
		return StreamTools.pollForError(
			function() {
				return DockerPromises.ping(docker);
			},
			PollType.regular,
			pollIntervalMilliseconds,
			maxRetries,
			doublingRetryIntervalMilliseconds);
	}

	public static function createDiskPoll(credentials :ConnectOptions, maxUsageCapacity :Float, pollType :PollType, pollIntervalMilliseconds: Int, maxRetries:Int, doublingRetryIntervalMilliseconds: Int) :Stream<Bool>
	{
		Assert.that(maxUsageCapacity != null);
		Assert.that(maxUsageCapacity > 0.0);
		Assert.that(maxUsageCapacity <= 1.0);
		var diskUse = ~/Filesystem.*Mounted on\n.+\s+.+\s+.+\s+([0-9]+)%.*/;
		return StreamTools.pollForError(
			function() {
				//   Filesystem      Size  Used Avail Use% Mounted on
				//   /dev/xvda9      5.5G  1.3G  4.0G  24% /
				return SshTools.execute(credentials, 'df -h /var/lib/docker/', 1)
					.then(function(out) {
						if (out.code == 0 && diskUse.match(out.stdout)) {
							return Std.parseFloat(diskUse.matched(1)) / 100.0;
						} else {
							return 0.0;
						}
					})
					.then(function(fractionUsed) {
						if (fractionUsed > maxUsageCapacity) {
							throw 'fractionUsed > maxUsageCapacity ($fractionUsed > $maxUsageCapacity)';
						}
						return true;
					});
			},
			PollType.regular,
			pollIntervalMilliseconds,
			maxRetries,
			doublingRetryIntervalMilliseconds);
	}

	public var status (get, null):Stream<MachineConnectionStatus>;
	public var docker (get, null):Stream<StatusDocker>;
	public var disk (get, null):Stream<StatusDisk>;

	var _status :PublicStream<MachineConnectionStatus> = PublicStream.publicstream(MachineConnectionStatus.Connecting);
	var _docker :PublicStream<StatusDocker> = PublicStream.publicstream(StatusDocker.NotConfigured);
	var _disk :PublicStream<StatusDisk> = PublicStream.publicstream(StatusDisk.NotConfigured);

	var _dockerPoll :Stream<Void>;
	var _diskPoll :Stream<Void>;

	public function new ()
	{
		//If there's a critical failure, dispose ourselves.
		//There is no recovery of this class once we hit a critical failure
		//The underlying resource is meant to be permanently disposed off.
		_status.then(function(machineStatus :MachineConnectionStatus) {
			switch(machineStatus) {
				case CriticalFailure(failure): dispose();
				default://Ignored
			}
		});
		_docker.then(function(dockerStatus) {
			switch(dockerStatus) {
				case NotConfigured,Connecting:
				case OK:
					_status.resolve(MachineConnectionStatus.OK);
				case ContactLost:
					_status.resolve(MachineConnectionStatus.CriticalFailure(MachineFailureType.DockerConnectionLost));
			}
		});
		_disk.then(function(diskStatus) {
			switch(diskStatus) {
				case NotConfigured,Connecting:
				case OK:
					_status.resolve(MachineConnectionStatus.OK);
				case DiskSpaceExceeded:
					_status.resolve(MachineConnectionStatus.CriticalFailure(MachineFailureType.DiskCapacityCritical));
			}
		});
	}

	public function dispose()
	{
		if (_docker != null) {
			_docker.end();
			_docker = null;
		}
		if (_disk != null) {
			_disk.end();
			_disk = null;
		}
		if (_status != null) {
			_status.end();
			_status = null;
		}
		if (_dockerPoll != null) {
			_dockerPoll.end();
			_dockerPoll = null;
		}

		if (_diskPoll != null) {
			_diskPoll.end();
			_diskPoll = null;
		}
	}

	public function monitorDocker(cred :DockerConnectionOpts, ?pollIntervalMilliseconds :Int = 1000, ?maxRetries :Int = 3, ?doublingRetryIntervalMilliseconds :Int = 500)
	{
		Assert.notNull(cred);
		if (_dockerPoll != null) {
			_dockerPoll.end();
			_dockerPoll = null;
		}
		if (cred.timeout == null) {
			cred.timeout = 2000;
		}

		_dockerPoll = createDockerPoll(cred, PollType.regular, pollIntervalMilliseconds, maxRetries, doublingRetryIntervalMilliseconds)
			.then(function(ok) {
				if (_docker != null) {
					if (ok) {
						_docker.resolve(StatusDocker.OK);
					} else {
						_docker.resolve(StatusDocker.ContactLost);
					}
				}
			});
		return this;
	}

	public function monitorDiskSpace(cred :ConnectOptions, ?maxDiskUsage :Float = 0.85, ?pollIntervalMilliseconds :Int = 1000, ?maxRetries :Int = 3, ?doublingRetryIntervalMilliseconds :Int = 500)
	{
		Assert.notNull(cred);
		if (_diskPoll != null) {
			_diskPoll.end();
			_diskPoll = null;
		}
		_diskPoll = createDiskPoll(cred, maxDiskUsage, PollType.regular, pollIntervalMilliseconds, maxRetries, doublingRetryIntervalMilliseconds)
			.then(function(ok) {
				if (_disk != null) {
					if (ok) {
						_disk.resolve(StatusDisk.OK);
					} else {
						_disk.resolve(StatusDisk.DiskSpaceExceeded);
					}
				}
			});
		return this;
	}

	function get_status()
	{
		return _status;
	}

	function get_docker()
	{
		return _docker;
	}

	function get_disk()
	{
		return _disk;
	}
}