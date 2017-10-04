package ccc;

/**
 * Don't change the BAD prefix from the bad health statuses, they're
 * used by redis internally to disambiguate from OK.
 */
@:enum
abstract WorkerHealthStatus(String) from String to String {
	var OK = 'OK';
	var BAD_DiskFull = 'BAD_DiskFull';
	var BAD_DockerDaemonUnreachable = 'BAD_DockerDaemonUnreachable';
	var BAD_Unknown = 'BAD_Unknown';
	var NULL = 'NULL';
}