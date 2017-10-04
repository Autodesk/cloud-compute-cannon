package ccc;

import t9.abstracts.net.HostName;

typedef InstanceDefinition = {
	var id :MachineId;
	var hostPublic :HostName;
	var hostPrivate :HostName;
// #if (nodejs && !macro && !clientjs)
// 	// var ssh :ConnectOptions;
// 	var docker :DockerConnectionOpts;
// #else
// 	// var ssh :Dynamic;
// 	var docker :Dynamic;
// #end
}