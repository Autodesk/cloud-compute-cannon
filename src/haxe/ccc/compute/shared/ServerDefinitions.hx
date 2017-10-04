package ccc.compute.shared;

import ccc.*;
import ccc.Definitions;
import ccc.storage.StorageDefinition;

import haxe.DynamicAccess;

import t9.abstracts.time.*;
import t9.abstracts.net.*;

typedef ServiceConfiguration = {
#if (nodejs && !macro && !clientjs)
	@:optional var storage: StorageDefinition;
	@:optional var providers: Array<ServiceConfigurationWorkerProvider>;
#else
	@:optional var storage: Dynamic;
	@:optional var providers: Array<Dynamic>;
#end
}

typedef ENV = {
	@:optional var PORT: Int;
	@:optional var REDIS_PORT: Int;
	@:optional var REDIS_HOST: String;
}

/* This is only used when creating worker providers in code */
@:enum
abstract ServiceWorkerProviderType(MachinePoolId) from MachinePoolId to MachinePoolId {
  var boot2docker = new MachinePoolId("Boot2Docker");
  var pkgcloud = new MachinePoolId("PkgCloud");
  var mock = new MachinePoolId("Mock");
  var test1 = new MachinePoolId("test1");
  var test2 = new MachinePoolId("test2");
}

typedef ProviderInstanceDefinition = {
	/* Workers typically are not exposed to the internet, while servers are */
	@:optional var public_ip :Bool;
	/* Not all platforms support tagging */
	@:optional var tags :DynamicAccess<String>;
	/* These are specific to the provider e.g. AWS */
	@:optional var options :Dynamic;
	/* SSH key for this machine. May be defined in parent (shared with other definitions) */
	@:optional var key :String;
}

@:enum
abstract MachineType(String) from String to String {
  var server = "server";
  var worker = "worker";
}

@:forward
abstract CloudProvider(ServiceConfigurationWorkerProvider) from ServiceConfigurationWorkerProvider to ServiceConfigurationWorkerProvider
{
	inline function new (val: ServiceConfigurationWorkerProvider)
		this = val;

	/**
	 * Some fields are in the parent object as shared defaults, so
	 * make sure to copy them
	 * @param  key :String       [description]
	 * @return     [description]
	 */
	inline public function getMachineDefinition(machineType :String) :ProviderInstanceDefinition
	{
		var instanceDefinition :ProviderInstanceDefinition = this.machines[machineType];
		if (instanceDefinition == null) {
			return null;
		}
		instanceDefinition = Json.parse(Json.stringify(instanceDefinition));
		instanceDefinition.public_ip = instanceDefinition.public_ip == true;
		instanceDefinition.tags = instanceDefinition.tags == null ? {} : instanceDefinition.tags;
		instanceDefinition.tags = ObjectTools.mergeDeepCopy(
			instanceDefinition.tags == null ? {} : instanceDefinition.tags,
			this.tags);
		instanceDefinition.options = ObjectTools.mergeDeepCopy(
			instanceDefinition.options == null ? {} : instanceDefinition.options,
			this.options);
		return instanceDefinition;
	}

	inline public function getShortName() :String
	{
		return switch(this.type) {
			case boot2docker: 'local';
			case pkgcloud:
				var credentials :js.npm.pkgcloud.PkgCloud.ClientOptionsAmazon = this.credentials;
				credentials.provider + '';
			default: 'unknown';
		}
	}

	inline public function getMachineKey(machineType :String) :String
	{
		var instanceDefinition :ProviderInstanceDefinition = this.machines[machineType];
		if (instanceDefinition == null) {
			throw 'Missing definition for machine="$machineType", cannot get key';
		}
		if (instanceDefinition.key != null) {
			return instanceDefinition.key;
		} else {
			//Assuming AWS
			var keyname = instanceDefinition.options.KeyName;
			if (keyname == null) {
				keyname = this.options.KeyName;
			}
			if (keyname == null) {
				throw 'No key name defined anywhere.';
			}
			return this.keys[keyname];
		}
	}
}

typedef ServiceConfigurationWorkerProvider = {
	var maxWorkers :Int;
	var minWorkers :Int;
	var priority :Int;
	var billingIncrement :Minutes;
	/* How often to check the queue, creating a worker if needed */
	var scaleUpCheckInterval :String;
	/* Waits this time interval in between adding a worker and checking the queue again */
	var workerCreationDuration :String;
	/* This is only optional if it has been previously set, and you are adjusting the above values only */
	@:optional var type: ServiceWorkerProviderType;
	/* Credentials to pass to third party libraries to access provider API */
	@:optional var credentials :Dynamic;
	/* Not all platforms support tagging instances yet. These tags are applied to all instances */
	@:optional var tags :DynamicAccess<String>;
	/* These options are common to all instances */
	@:optional var options :Dynamic;
	/* SSH keys for connecting to the instances */
	@:optional var keys :DynamicAccess<String>;
	@:optional var machines :DynamicAccess<ProviderInstanceDefinition>;
}


/**
 *********************************************
 * CLI definitions
 **********************************************
 */

typedef ServerConnectionBlob = {
	var host :Host;
	/**
	 * If server is missing, the server ssh config is pulled from ~/.ssh/config
	 */
	@:optional var server :InstanceDefinition;
	@:optional var provider: ServiceConfiguration;
}

typedef ServerVersionBlob = {
	var npm :String;
	var compiler :String;
	var instance :String;
	var git :String;
	var compile_time :String;
	@:optional var VERSION :String;
}

typedef ClientVersionBlob = {
	var npm :String;
	var compiler :String;
}

@:enum
abstract JobCLICommand(String) from String {
	/* Does not remove the job results in the storage service */
	var Remove = 'remove';
	var RemoveComplete = 'removeComplete';
	var Status = 'status';
	var ExitCode = 'exitcode';
	var Kill = 'kill';
	var Result = 'result';
	var Definition = 'definition';
	var JobStats = 'stats';
	var Time = 'time';
}

enum CLIResult {
	PrintHelp;
	PrintHelpExit1;
	ExitCode(code :Int);
	Success;
}

abstract CLIServerPathRoot(String) from String
{
	inline public function new(s :String)
		this = s;

#if (js && !macro)

	inline public function getServerYamlConfigPath() :String
	{
		return js.node.Path.join(this, Constants.LOCAL_CONFIG_DIR, Constants.SERVER_CONNECTION_FILE);
	}

	inline public function getServerYamlConfigPathDir() :String
	{
		return js.node.Path.join(this, Constants.LOCAL_CONFIG_DIR);
	}

	inline public function getLocalServerPath() :String
	{
		return js.node.Path.join(this, Constants.SERVER_LOCAL_DOCKER_DIR);
	}

	inline public function localServerPathExists() :Bool
	{
		var p = getLocalServerPath();
		try {
			var stats = js.node.Fs.statSync(p);
			return true;
		} catch (err :Dynamic) {
			return false;
		}
	}

#end

	public function toString() :String
	{
		return this;
	}
}
