package ccc.compute.shared;

import ccc.storage.StorageDefinition;

typedef ServiceConfiguration = {
#if (nodejs && !macro && !clientjs)
	@:optional var storage: StorageDefinition;
	@:optional var providers: Array<ServiceConfigurationWorkerProvider>;
#else
	@:optional var storage: Dynamic;
	@:optional var providers: Array<Dynamic>;
#end
}
