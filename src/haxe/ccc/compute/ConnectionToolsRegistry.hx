package ccc.compute;


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
			Assert.notNull(Constants.REGISTRY);
			return Constants.REGISTRY;
			// var isInContainer = ConnectionToolsDocker.isInsideContainer();
			// // var address :String = Constants.SERVER_HOSTNAME_PRIVATE;
			// var address :String = isInContainer ? Constants.SERVER_HOSTNAME_PRIVATE : ConnectionToolsDocker.getDockerHost();
			// var port = REGISTRY_DEFAULT_PORT;
			// return new Host(new HostName(address), new Port(port));
		}
	}
}