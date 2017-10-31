package ccc.compute.shared;

import t9.abstracts.time.*;

typedef ServiceConfigurationWorkerProvider = {
	var maxWorkers :Int;
	var minWorkers :Int;
	var priority :Int;
	var billingIncrement :Minutes;
	/* How often to check the queue, creating a worker if needed */
	var scaleUpCheckInterval :String;
	/* Waits this time interval in between adding a worker and checking the queue again */
	var workerCreationDuration :String;
	/* Credentials to pass to third party libraries to access provider API */
	@:optional var credentials :Dynamic;
	/* Not all platforms support tagging instances yet. These tags are applied to all instances */
	@:optional var tags :DynamicAccess<String>;
	/* These options are common to all instances */
	@:optional var options :Dynamic;
	/* SSH keys for connecting to the instances */
	@:optional var keys :DynamicAccess<String>;
	@:optional var machines :DynamicAccess<ProviderInstanceDefinition>;
	@:optional var type :String;
}
