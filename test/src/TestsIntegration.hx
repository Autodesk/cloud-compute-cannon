import js.Node;
import js.node.child_process.ChildProcess;

import haxe.unit.async.PromiseTestRunner;

import ccc.compute.server.ConnectionToolsDocker;
import ccc.compute.server.InitConfigTools;

using Lambda;
using StringTools;
using promhx.PromiseTools;

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

	static function tryToResolveClass(className :String) :Class<Dynamic>
	{
		var cls = Type.resolveClass(className);
		if (cls != null) {
			return cls;
		} else if (Type.resolveClass('ccc.compute.server.tests.$className') != null) {
			return Type.resolveClass('ccc.compute.server.tests.$className');
		} else if (Type.resolveClass('compute.$className') != null) {
			return Type.resolveClass('compute.$className');
		} else if (Type.resolveClass('ccc.docker.dataxfer.$className') != null) {
			return Type.resolveClass('ccc.docker.dataxfer.$className');
		} else if (Type.resolveClass('storage.$className') != null) {
			return Type.resolveClass('storage.$className');
		} else {
			return null;
		}
	}

	static function getClassAndMethod(s :String) :{cls :Class<Dynamic>, method :String}
	{
		var className = Sys.args()[0];
		var cls = tryToResolveClass(className);
		if (cls != null) {
			return {cls:cls, method:null};
		} else {
			var tokens = className.split('.');
			var methodName = tokens.pop();
			className = tokens.join('.');
			cls = tryToResolveClass(className);
			if (cls != null) {
				return {cls:cls, method:methodName};
			} else {
				return {cls:null, method:null};
			}
		}
	}

	static function main()
	{
		Node.require('dotenv').config({path: '.env.test', silent: true});
		if (Reflect.field(Node.process.env, ENV_VAR_DISABLE_LOGGING) == 'true') {
			untyped __js__('console.log = function() {}');
			Logger.log.level(100);
		}

		if (Sys.args().length == 0) {
			runTests();
		} else {
			var className = Sys.args()[0];
			var clsAndMethod = getClassAndMethod(className);
			var cls = clsAndMethod.cls;
			var methodName = clsAndMethod.method;
			if (cls != null) {
				if (methodName != null) {
					var ins :{setup:Void->Promise<Bool>,tearDown:Void->Promise<Bool>} = Type.createInstance(cls, []);
					var testMethod = Reflect.field(ins, methodName);
					if (testMethod != null) {
						Node.setTimeout(function(){}, 1000000000);
						ins.setup()
							.orTrue()
							.pipe(function(_) {
								var p :Promise<Bool> = Reflect.callMethod(ins, testMethod, []);
								return p.orTrue();
							})
							.errorPipe(function(err) {
								traceRed(err);
								return Promise.promise(false);
							})
							.pipe(function(result) {
								return ins.tearDown()
									.then(function(_) {
										return result;
									})
									.errorPipe(function(err) {
										traceRed(err);
										return Promise.promise(result);
									});
							})
							.then(function(passed){
								if (passed) {
									traceGreen('Passed!');
									Node.process.exit(0);
								} else {
									traceRed('Failed!');
									Node.process.exit(1);
								}
								return true;
							});
					} else {
						traceRed('No method ${className}.$methodName');
						Node.process.exit(1);
					}
				} else {
					var runner = new PromiseTestRunner();
					runner.add(Type.createInstance(cls, []));
					runner.run();
				}
			} else {
				traceRed('No class ${className}');
				Node.process.exit(1);
			}
		}
	}

	static function runTests()
	{
		TestMain.setupTestExecutable();

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

		//Disable these tests until we figure out how to inject S3 credentials outside of git
		//and test the CLI
		// runner.add(new ccc.compute.server.tests.TestStorageS3());
		// runner.add(new compute.TestCLIRemoteServerInstallation());
		// runner.add(new compute.TestCLISansServer());
		// runner.add(new compute.TestCLI());

		//Run the unit tests. These do not require any external dependencies
		if (isUnit) {
			runner.add(new utils.TestPromiseQueue());
			runner.add(new utils.TestStreams());
			runner.add(new storage.TestStorageRestAPI());
			runner.add(new ccc.compute.server.tests.TestStorageLocal(ccc.storage.ServiceStorageLocalFileSystem.getService()));
			runner.add(new compute.TestRedisMock());
			if (isInternet && !util.DockerTools.isInsideContainer()) {
				runner.add(new storage.TestStorageSftp());
			}
		}

		if (isRedis) {
			// These require a local redis db
			// runner.add(new compute.TestAutoscaling());
			// runner.add(new compute.TestRedis());

			//These require access to a local docker server
			if (isDockerProvider) {
				ccc.compute.workers.WorkerProviderBoot2Docker.setHostWorkerDirectoryMount();
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
		}

		if (isVagrant && isRedis) {
			runner.add(new compute.TestVagrant());
			runner.add(new compute.TestScalingVagrant());
			runner.add(new compute.TestCompleteJobSubmissionVagrant());
			runner.add(new compute.TestRestartAfterCrashVagrant());
		}

		if (isAws) {
			runner.add(new ccc.compute.server.tests.TestWorkerMonitoring());
			runner.add(new compute.TestPkgCloudAws());
			runner.add(new compute.TestScalingAmazon());
			runner.add(new compute.TestCompleteJobSubmissionAmazon());
			runner.add(new compute.TestRestartAfterCrashAWS());
		}

		runner.run();
	}
}