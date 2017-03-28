package ccc.compute.server.cwl;

class ServiceCWL
{
	public static var CWL_RUNNER_IMAGE = 'docker.io/dionjwa/cwltool-ccc:0.0.6';

	public function workflowRun(git :String, sha :String, cwl:String, input :String, ?inputs :DynamicAccess<String>) :Promise<JobResult>
	{
		return getContainerAlias()
			.pipe(function(containerAlias) {
				var inputs = inputs == null ? [] :
					inputs.keys().map(function(key) {
						var input :ComputeInputSource = {
							name: key,
							type: InputSource.InputInline,
							value: inputs.get(key)
						};
						return input;
					});


				var request :BasicBatchProcessRequest = {
					image: CWL_RUNNER_IMAGE,
					inputs: inputs,
					createOptions: {
						Image: CWL_RUNNER_IMAGE,
						Cmd: ['/root/bin/download-run-workflow', git, sha, cwl, input],
						Env: ['CCC=http://${containerAlias}:${SERVER_DEFAULT_PORT}${SERVER_RPC_URL}'],
						HostConfig: {
							Binds: [
								'/tmp/repos:/tmp/repos:rw'
							]
						}
					},
					mountApiServer: true,//Needed to hit the CCC server
					parameters: {cpus:1, maxDuration:259200},//3 days, it's a workflow
					wait: false,
					appendStdOut: true,
					appendStdErr: true,
					meta: {
						"type": "workflow",
						"job-type": "workflow"
					}
				};
				return _rpc.submitJobJson(request);
			});
	}

	public function testWorkflow() :Promise<Bool>
	{
		var test = new TestCWLApi();
		_injector.injectInto(test);
		return test.testWorkflowDynamicInput();
	}

	function getContainerAlias() :Promise<String>
	{
		var container = _docker.getContainer(DOCKER_CONTAINER_ID);
		return DockerPromises.inspect(container)
			.then(function(data :Dynamic) {
				return Reflect.field(data.Config.Labels, 'com.docker.compose.service');
			});
	}

	@inject public var _injector :Injector;
	@inject public var _docker :Docker;
	@inject public var _context :t9.remoting.jsonrpc.Context;
	@inject public var _rpc :RpcRoutes;
	@inject('localRPCApi') public var _rpcApiUrl :UrlString;

	@post
	public function postInject()
	{
		_context.registerService(this);
	}

	public function new(){}
}