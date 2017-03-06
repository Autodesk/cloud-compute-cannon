package ccc.compute.server.tests;

class ServerTestTools
{
	public static function getServerAddress() :Host
	{
		var env = Sys.environment();
		if (env.exists(ENV_VAR_CCC_ADDRESS)) {
			return env.get(ENV_VAR_CCC_ADDRESS);
		} else {
			return new Host(new HostName('localhost'), new Port(SERVER_HTTP_PORT));
		}
	}

	// public static function resetRemoteServer(host :Host) :Promise<Bool>
	// {
	// 	var serverHostRPCAPI = 'http://${host}${SERVER_RPC_URL}';
	// 	var proxy = getProxy(serverHostRPCAPI);
	// 	return proxy.serverReset();
	// }

	public static function getProxy(rpcUrl :UrlString)
	{
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.server.execution.routes.RpcRoutes, true)
			.setConnection(new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(rpcUrl));
		return proxy;
	}

	public static function getJobResult(jobId :JobId) :Promise<JobResult>
	{
		var proxy = getProxy(SERVER_LOCAL_RPC_URL);
		function getJobData() {
			return cast proxy.doJobCommand(JobCLICommand.Result, jobId);
		}
		return JobWebSocket.getJobResult(SERVER_LOCAL_HOST, jobId, getJobData);
	}
}