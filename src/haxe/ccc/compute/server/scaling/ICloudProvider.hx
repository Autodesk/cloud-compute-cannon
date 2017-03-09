package ccc.compute.server.scaling;

interface ICloudProvider
{
	public function getId() :Promise<MachineId>;

	public function getHostPublic() :Promise<String>;

	public function getHostPrivate() :Promise<String>;

	public function getDiskUsage() :Promise<Float>;

	/**
	 * Given that e.g. AWS instances are billed per hour,
	 * return the time where shutting down is most cost
	 * effective (just before the next billing cycle)
	 * @return [description]
	 */
	public function getBestShutdownTime() :Promise<Float>;

	/**
	 * Actually shut down this instance.
	 * @return [description]
	 */
	public function shutdownThisInstance() :Promise<Bool>;

	/**
	 * Actually shut down this instance.
	 * @return [description]
	 */
	public function createWorker() :Promise<Bool>;

	/**
	 * Shut down a sick worker.
	 * @return [description]
	 */
	public function terminate(id :MachineId) :Promise<Bool>;

	/**
	 * Shuts down any timers, resources, etc
	 * @return [description]
	 */
	public function dispose() :Promise<Bool>;
}