package ccc;

@:enum
abstract JobFinishedStatus(String) to String {

	/**
	 * Success simply means the docker container ran, then eventually exited.
	 * The container can exit with a non-zero exit code, this is still
	 * considered a 'success'.
	 */
	var Success = 'success';

	/**
	 * Long running jobs will be killed
	 */
	var TimeOut = 'timeout';

	/** A failed job means that there is some user error or system error
	 *  that prevents the docker container starting, or an error
	 *  running or copying job data. For example, relying
	 *  on a docker image that does not exist.
	 */
	var Failed = 'failed';

	/**
	 * Users can kill jobs.
	 */
	var Killed = 'killed';

	/**
	 * Don't let failed jobs retry forever
	 */
	var TooManyFailedAttempts = 'TooManyFailedAttempts';

	/**
	 * Placeholder initialized status. It means the job is NOT finished.
	 */
	var None = 'none';
}