package compute;

class TestRestartAfterCrashLocalDocker extends TestRestartAfterCrashBase
{
	public function new() {super();}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.then(function(_) {
				_env = cast Reflect.copy(js.Node.process.env);
				Reflect.setField(_env, ENV_LOG_LEVEL, 70);//js.npm.bunyan.Bunyan.WARN);
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