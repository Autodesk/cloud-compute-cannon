package compute;

import promhx.Promise;

import ccc.compute.server.InitConfigTools;

class TestRestartAfterCrashAWS extends TestRestartAfterCrashBase
{
	public function new() {super();}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.then(function(_) {
				_env = cast Reflect.copy(js.Node.process.env);
				var config = InitConfigTools.getConfigFromEnv();
				if (config == null || !InitConfigTools.isPkgCloudConfigured(config)) {
					_env = null;
				}
				return true;
			});
	}

	@timeout(12000000)
	function testRestartAfterCrashAWS()
	{
		if (_env != null) {
			return baseTestRestartAfterCrash();
		} else {
			throw 'Missing config in process.env';
			return Promise.promise(true);
		}
	}
}