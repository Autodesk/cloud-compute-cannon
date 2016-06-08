package ccc.compute;

import ccc.compute.Definitions.Constants.*;

import t9.abstracts.net.*;

/**
 * Tools for finding, saving, and getting the address(s?) of
 * the docker registry where worker images are stored and
 * pulled.
 */
class ConnectionToolsRegistry
{
	public static function getRegistryAddress() :Host
	{
		var env = js.Node.process.env;
		trace(sys.io.File.getContent('/etc/hosts'));
		if (Reflect.hasField(env, ENV_VAR_ADDRESS_REGISTRY) && Reflect.field(env, ENV_VAR_ADDRESS_REGISTRY) != null && Reflect.field(env, ENV_VAR_ADDRESS_REGISTRY) != '') {
			var host :Host = Reflect.field(env, ENV_VAR_ADDRESS_REGISTRY);
			return host;
		} else {
			var isInContainer = ConnectionToolsDocker.isInsideContainer();
			// var address :String = isInContainer ? REGISTRY_HOST_IN_ETC : ConnectionToolsDocker.getDockerHost();
			var address = REGISTRY_HOST_IN_ETC;
			var port = REGISTRY_DEFAULT_PORT;//isInContainer ? REGISTRY_DEFAULT_PORT - 1 : REGISTRY_DEFAULT_PORT;
			return new Host(new HostName(address), new Port(port));
		}
	}
}