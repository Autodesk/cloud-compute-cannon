package ccc;

@:enum
abstract JobStatus(String) from String {
	/**
	 * The job is in the queue.
	 * Set in Redis, not handled elsewhere.
	 */
	var Pending = 'pending';
	/**
	 * The job is loaded, inputs, copied, etc.
	 * The JobWorkingStatus tracks the granular working process.
	 * Set in Redis, not handled elsewhere.
	 */
	var Working = 'working';
	/**
	 * When the Job object is finished finalizing the job, it marks
	 * the job as finished.
	 */
	var Finished = 'finished';
}