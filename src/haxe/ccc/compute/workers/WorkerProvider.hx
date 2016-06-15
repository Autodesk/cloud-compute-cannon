package ccc.compute.workers;
/**
 * I'm not completely sure about this service. I need to think a
 * bit more about it.
 */

import js.npm.RedisClient;

import ccc.compute.InstancePool;

import promhx.Promise;

import t9.abstracts.net.*;

interface WorkerProvider
{
	var id (default, null) :String;
	var redis (get, null) :RedisClient;
	var ready (get, null) :Promise<Bool>;
	var log (default, null) :AbstractLogger;

	function updateConfig(config :ProviderConfigBase) :Promise<Bool>;

	function setPriority(val :Int) :Promise<Bool>;
	function setMaxWorkerCount(val :WorkerCount) :Promise<Bool>;
	function setWorkerCount(val :WorkerCount) :Promise<Bool>;

	function removeWorker(id :MachineId) :Promise<Bool>;
	function createWorker() :Promise<WorkerDefinition>;

	/**
	 * This worker is NOT integrated into the queue system,
	 * or the compute pool management. It's a utility method
	 * for other objects to create workers using the logic
	 * and config contained in this class. For example, when
	 * calling shutdownAllWorkers(), workers returned from
	 * this call are NOT shut down.
	 * @return [description]
	 */
	function createIndependentWorker() :Promise<WorkerDefinition>;

	/**
	 * Called from the CLI to create a server from this config.
	 * @return [description]
	 */
	function createServer() :Promise<InstanceDefinition>;
	function destroyInstance(id :MachineId) :Promise<Bool>;

	function getNetworkHost() :Promise<Host>;

	/**
	 * This is currently only used to prevent tests from conflicting,
	 * since in production there should not be a reason to remove
	 * an entire compute pool provider.
	 * @return [description]
	 */
	function dispose() :Promise<Bool>;

	function shutdownAllWorkers() :Promise<Bool>;

#if debug
	function getTargetWorkerCount() :Int;
	function whenFinishedCurrentChanges() :Promise<Bool>;
#end
}