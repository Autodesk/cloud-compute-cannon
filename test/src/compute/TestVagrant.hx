package compute;

class TestVagrant extends TestComputeBase
{
	public static var ROOT_PATH = 'tmp/TestVagrant/';
	var _address :String;
	var _machinePath :String;

	public function new()
	{
		_address = '192.168.' + Math.max(1, Math.floor(Math.random() * 254)) + '.' + Math.max(1, Math.floor(Math.random() * 254));
		_machinePath = ROOT_PATH + _address.replace('.', '_');
	}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				throw 'BROKEN: what is the registry host here?';
				return WorkerProviderVagrantTools.ensureWorkerBox(_machinePath, _address, null, _streams)
					.thenTrue();
			});
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		return super.tearDown()
			.pipe(function(_) {
				return VagrantTools.remove(_machinePath, true, _streams);
			});
	}

	@timeout(60000)
	public function testVagrantSshConnection()
	{
		return WorkerProviderVagrantTools.getSshConfig(_machinePath)
			.pipe(function(config :ConnectOptions) {
				return SshTools.execute(config, 'echo "Hello"');
			})
			.then(function(result) {
				assertEquals('Hello', result.stdout.trim());
				return true;
			});
	}

	@timeout(60000)
	public function testDockerConnection()
	{
		var ssh;
		var sshConfig;
		return WorkerProviderVagrantTools.getDockerConfig(_machinePath)
			// .traceJson()
			.pipe(function(dockerConfig) {
				var docker = new Docker(dockerConfig);
				return DockerPromises.info(docker);
			})
			// .traceJson()
			.then(function(out) {
				assertTrue(Reflect.hasField(out, 'ID'));
				assertTrue(Reflect.hasField(out, 'Containers'));
				return true;
			});
	}
}