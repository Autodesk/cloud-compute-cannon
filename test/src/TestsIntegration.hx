import js.Node;
import js.node.child_process.ChildProcess;

import haxe.unit.async.PromiseTestRunner;

import ccc.compute.InitConfigTools;

using Lambda;
using StringTools;

class TestsIntegration
{
	public static inline function detectVagrant() :Bool
	{
		var isVagrant = false;
		try {
			var stdout :String = js.node.ChildProcess.execSync("which vagrant", {stdio:['ignore','pipe','ignore']});
			isVagrant = Std.string(stdout).trim().startsWith('/usr/local');
		} catch (ignored :Dynamic) {
			// do nothing
		}
		return isVagrant && !isDisabled('VAGRANT');
	}

	public static inline function detectPkgCloud() :Bool
	{
		var isPkgCloud = InitConfigTools.getConfigFromEnv() != null ? InitConfigTools.isPkgCloudConfigured(InitConfigTools.getConfigFromEnv()) : false;
		return isPkgCloud && !isDisabled('AWS');
	}

	static inline function isDisabled(key :String) :Bool
	{
		var env = js.Node.process.env;
		if (Reflect.field(env, key) == 'false' || Reflect.field(env, key) == '0') {
			return true;
		} else {
			return false;
		}
	}

	static inline function unitOnly() :Bool
	{
		var env = js.Node.process.env;
		if (Reflect.field(env, 'UNITONLY') == 'true') {
			return true;
		} else {
			return false;
		}
	}

	static function main()
	{
		var bunyanLogger :js.npm.Bunyan.BunyanLogger = Logger.log;
		bunyanLogger.level(js.npm.Bunyan.WARN);

		//Required for source mapping
		js.npm.SourceMapSupport;
		util.EmbedMacros.embedFiles('etc');
		ErrorToJson;

		//Prevents warning messages since we have a lot of streams piping to the stdout/err streams.
		js.Node.process.stdout.setMaxListeners(20);
		js.Node.process.stderr.setMaxListeners(20);

		var isRedis = !isDisabled('REDIS');
		var isAws = detectPkgCloud();
		var isVagrant = detectVagrant();
		var isDockerProvider = !isDisabled('DOCKER');
		var isInternet = !isDisabled('INTERNET');
		var isUnit = !isDisabled('UNIT');

		if (unitOnly()) {
			isUnit = true;
			isRedis = false;
			isAws = false;
			isVagrant = false;
			isDockerProvider = false;
			isInternet = false;
		}

		//Vagrant is currently disabled as the tests are broken.
		isVagrant = false;

		var runner = new PromiseTestRunner();

		//Run the unit tests. These do not require any external dependencies
		if (isUnit) {
			runner.add(new utils.TestMiscUnit());
			runner.add(new utils.TestPromiseQueue());
			runner.add(new utils.TestStreams());
			runner.add(new storage.TestStorageRestAPI());
			runner.add(new storage.TestStorageLocal());
			runner.add(new compute.TestRedisMock());
			if (isInternet) {
				runner.add(new storage.TestStorageSftp());
			}
		}

		if (isRedis) {
			// These require a local redis db
			runner.add(new compute.TestAutoscaling());
			runner.add(new compute.TestRedis());

			//These require access to a local docker server
			if (isDockerProvider) {
				runner.add(new compute.TestScheduler());
				runner.add(new compute.TestJobStates());
				runner.add(new compute.TestInstancePool());
				runner.add(new compute.TestComputeQueue());
				runner.add(new compute.TestScalingMock());

				runner.add(new compute.TestCompleteJobSubmissionLocalDocker());
				runner.add(new compute.TestRestartAfterCrashLocalDocker());
				runner.add(new compute.TestDockerCompute());
				runner.add(new compute.TestServiceBatchCompute());
			}

			// runner.add(new compute.TestCLIRemoteServerInstallation());
			// runner.add(new compute.TestJobStates());
			//CLI
			// runner.add(new compute.TestCLISansServer());
			// runner.add(new compute.TestCLI());
		}

		if (isVagrant && isRedis) {
			runner.add(new compute.TestVagrant());
			runner.add(new compute.TestScalingVagrant());
			runner.add(new compute.TestCompleteJobSubmissionVagrant());
			runner.add(new compute.TestRestartAfterCrashVagrant());
		}

		if (isAws) {
			runner.add(new compute.TestPkgCloudAws());
			runner.add(new compute.TestScalingAmazon());
			runner.add(new compute.TestCompleteJobSubmissionAmazon());
			runner.add(new compute.TestRestartAfterCrashAWS());
		}

		runner.run();
	}
}