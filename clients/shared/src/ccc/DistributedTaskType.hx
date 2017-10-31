package ccc;

@:enum
abstract DistributedTaskType(String) from String to String {
	var CheckAllWorkerHealth = 'CheckAllWorkerHealth';
	var RunScaling = 'RunScaling';
}
