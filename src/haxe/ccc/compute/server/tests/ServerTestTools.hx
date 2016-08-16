package ccc.compute.server.tests;

class ServerTestTools
{
	public static function getServerAddress() :Host
	{
		var env = Node.process.env;
		if (Reflect.hasField(env, ENV_VAR_CCC_ADDRESS)) {
			return Reflect.field(env, ENV_VAR_CCC_ADDRESS);
		} else {
			return new Host(new HostName('localhost'), new Port(SERVER_HTTP_PORT));
		}
	}

	public static function resetRemoteServer(host :Host) :Promise<Bool>
	{
		var serverHostRPCAPI = 'http://${host}${SERVER_RPC_URL}';
		var proxy = getProxy(serverHostRPCAPI);
		return proxy.serverReset();
	}

	public static function getProxy(rpcUrl :UrlString)
	{
		var proxy = t9.remoting.jsonrpc.Macros.buildRpcClient(ccc.compute.ServiceBatchCompute, true)
			.setConnection(new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(rpcUrl));
		return proxy;
	}

	public static function getJobResult(jobId :JobId) :Promise<JobResult>
	{
		var proxy = getProxy(SERVER_LOCAL_RPC_URL);
		function getJobData() {
			return proxy.doJobCommand(JobCLICommand.Result, [jobId], true)
				.then(function(out) {
					return out[jobId];
				});
		}
		return JobWebSocket.getJobResult(SERVER_LOCAL_HOST, jobId, getJobData);
	}
}