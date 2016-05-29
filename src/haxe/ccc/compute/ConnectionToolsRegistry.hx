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
		if (Reflect.hasField(env, ENV_VAR_ADDRESS_REGISTRY) && Reflect.field(env, ENV_VAR_ADDRESS_REGISTRY) != null && Reflect.field(env, ENV_VAR_ADDRESS_REGISTRY) != '') {
			var host :Host = Reflect.field(env, ENV_VAR_ADDRESS_REGISTRY);
			return host;
		} else {
			return new Host(new HostName(SERVER_HOSTNAME_PRIVATE), new Port(REGISTRY_DEFAULT_PORT));
		}
	}
}