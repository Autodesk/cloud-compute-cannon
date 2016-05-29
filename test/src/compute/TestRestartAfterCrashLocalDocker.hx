package compute;

import ccc.compute.Definitions.Constants.*;

import promhx.Promise;

class TestRestartAfterCrashLocalDocker extends TestRestartAfterCrashBase
{
	public function new() {super();}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.then(function(_) {
				_env = cast Reflect.copy(js.Node.process.env);
				_env.remove(ENV_VAR_COMPUTE_CONFIG);
				return true;
			});
	}

	@timeout(30000)
	function testRestartAfterCrashLocalDocker()
	{
		return baseTestRestartAfterCrash();
	}
}