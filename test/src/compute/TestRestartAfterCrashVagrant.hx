package compute;

class TestRestartAfterCrashVagrant extends TestRestartAfterCrashBase
{
	public function new() {super();}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.then(function(_) {
				_env = cast Reflect.copy(js.Node.process.env);
				Reflect.setField(_env, ENV_VAR_COMPUTE_CONFIG, js.node.Fs.readFileSync('etc/config/serverconfig.vagrant.template.yml', {encoding:'utf8'}));
				return true;
			})
			.pipe(function(_) {
				return WorkerProviderVagrant.destroyAllVagrantMachines();
			});
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		return super.tearDown()
			.pipe(function(_) {
				return WorkerProviderVagrant.destroyAllVagrantMachines();
			});
	}

	@timeout(12000000)
	function testRestartAfterCrashVagrant()
	{
		if (Reflect.hasField(_env, ENV_VAR_COMPUTE_CONFIG)) {
			return baseTestRestartAfterCrash();
		} else {
			return Promise.promise(true);
		}
	}
}