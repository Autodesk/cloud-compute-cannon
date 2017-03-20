package ccc.compute.server.cwl;

import ccc.compute.client.js.ClientJSTools;

import js.npm.shortid.ShortId;

class TestCWLApi extends ServerAPITestBase
{
	public static var TEST_BASE = 'tests';
	@inject public var _cwl :ServiceCWL;
	@inject public var _rpc :RpcRoutes;

	@timeout(240000)
	public function testWorkflowDynamicInput() :Promise<Bool>
	{
		//http://localhost:9001/metaframe/cwl?git=https://github.com/dionjwa/cwltool&sha=e7e6e18f62cf5db6541f15fedcee47ae0e219bbf&cwl=tests/ccc_docker_workflow/run_workflow.cwl&input=tests/ccc_docker_workflow/input.yml
		var git = 'https://github.com/dionjwa/cwltool';
		var sha = 'e7e6e18f62cf5db6541f15fedcee47ae0e219bbf';
		var cwl = 'tests/ccc_docker_workflow/run_workflow.cwl';

		var inputDeclarationFileName = 'input.yml';
		var input = '/inputs/$inputDeclarationFileName';
		var inputFileName = 'inputTest';
		var testValue = 'testValue${ShortId.generate()}';
		var inputs :DynamicAccess<String> = {};
		inputs.set(inputDeclarationFileName, '
infile:
  class: File
  path: /inputs/$inputFileName
');
		inputs.set(inputFileName, testValue);

		return _cwl.workflowRun(git, sha, cwl, input, inputs)
			.pipe(function(jobResult) {
				return _rpc.getJobResult(jobResult.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				assertTrue(jobResult.outputs.length == 1);
				assertEquals(jobResult.outputs[0], 'outfile2');
				var outputUrl1 = jobResult.getOutputUrl(jobResult.outputs[0]);
				return RequestPromises.get(outputUrl1)
					.then(function(out) {
						out = out != null ? out.trim() : out;
						assertEquals(out, testValue);
						return true;
					});
			});
	}

	@timeout(240000)
	public function testWorkflowNoExtraInput() :Promise<Bool>
	{
		//http://localhost:9001/metaframe/cwl?git=https://github.com/dionjwa/cwltool&sha=e7e6e18f62cf5db6541f15fedcee47ae0e219bbf&cwl=tests/ccc_docker_workflow/run_workflow.cwl&input=tests/ccc_docker_workflow/input.yml
		var git = 'https://github.com/dionjwa/cwltool';
		var sha = 'e7e6e18f62cf5db6541f15fedcee47ae0e219bbf';
		var cwl = 'tests/ccc_docker_workflow/run_workflow.cwl';
		var input = 'tests/ccc_docker_workflow/input.yml';

		return _cwl.workflowRun(git, sha, cwl, input)
			.pipe(function(jobResult) {
				return _rpc.getJobResult(jobResult.jobId);
			})
			.pipe(function(jobResult :JobResultAbstract) {
				assertTrue(jobResult.outputs.length == 1);
				assertEquals(jobResult.outputs[0], 'outfile2');
				var outputUrl1 = jobResult.getOutputUrl(jobResult.outputs[0]);
				return RequestPromises.get(outputUrl1)
					.then(function(out) {
						out = out != null ? out.trim() : out;
						assertEquals(out, 'foobar');
						return true;
					});
			});
	}

	public function new()
	{
		super();
	}
}