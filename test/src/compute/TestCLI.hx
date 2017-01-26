package compute;

import batcher.cli.ProviderTools.*;
import batcher.cli.CliTools.*;
import ccc.compute.workers.WorkerProviderBoot2Docker;

import js.Node;
import js.node.ChildProcess;
import js.node.Os;
import js.node.Path;

import js.npm.fsextended.FsExtended;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

import js.node.ChildProcess;

import utils.TestTools;

import t9.abstracts.net.Host;

using promhx.PromiseTools;
using StringTools;

class TestCLI extends TestComputeBase
{
	var host :Host = 'localhost:${Constants.SERVER_DEFAULT_PORT}';
	static var TESTS_BASE_PATH = 'tmp/TestCLI';
	static var CLI_PATH = '../../build/cli/cloudcannon';

	static function runCliCommand(command :String) :Promise<Dynamic>
	{
		var promise = new DeferredPromise();

		var exitCode = 0;
		var process = ChildProcess.exec(command, {cwd:Path.join(Node.process.cwd(), TESTS_BASE_PATH)}, function(error, stdout, stderr) {
			if (error != null) {
				Log.error(error);
				promise.boundPromise.reject(error);
				return;
			}
			if (exitCode != 0) {
				Log.error('exitCode=$exitCode');
				Log.error(stderr.toString());
				promise.boundPromise.reject(stderr.toString().trim());
				return;
			}
			promise.resolve(stdout.toString());
		});
		return promise.boundPromise;
	}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				//Compile the CLI
				var out = untyped __js__('require("child_process").execSync("haxe etc/hxml/cli-build.hxml")');
				//Create a server in a forked process
				return TestTools.forkServerCompute()
					.then(function(serverprocess) {
						_childProcess = serverprocess;
						return true;
					});
			})
			.then(function(_) {
				//Create the paths
				FsExtended.deleteDirSync(TESTS_BASE_PATH);
				var serverBlob :ServerConnectionBlob = {server:WorkerProviderBoot2Docker.getLocalDockerWorker()};
				writeServerConnection(TESTS_BASE_PATH, serverBlob);
				return true;
			});
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		FsExtended.deleteDirSync(TESTS_BASE_PATH);
		return super.tearDown();
	}

	// @timeout(10000)
	// public function testLocalServerRunning()
	// {
	// 	var host :Host = 'localhost:${Constants.SERVER_DEFAULT_PORT}';
	// 	return serverCheck('localhost:${Constants.SERVER_DEFAULT_PORT}');
	// }

	// public function testGetCorrectLocalServerHost()
	// {
	// 	return Promise.promise(true)
	// 		.pipe(function(_) {
	// 			return getServerAddress()
	// 				.then(function(host) {
	// 					var localhost :Host = 'localhost:${Constants.SERVER_DEFAULT_PORT}';
	// 					assertEquals(host, localhost);
	// 					return true;
	// 				});
	// 		});
	// }

	@timeout(10000)
	public function testJobDelete()
	{
		//Create a job
		return Promise.promise(true)
			.pipe(function(_) {
				var command = '$CLI_PATH --help';
				return runCliCommand(command);
			})
			.then(function(out) {
				return true;
			})
			.pipe(function(_) {
				//Run a job that lasts 20s
				var command = '$CLI_PATH run --image ${Constants.DOCKER_IMAGE_DEFAULT} sleep 20';
				trace('command=${command}');
				return runCliCommand(command);
			})
			.then(function(out) {
				trace('out=${out}');
				return true;
			})
			;
		//Job finishes
		//Check retrieving job info
		//Delete job for good
		//Check retrieving job info again
		// var jobId :JobId;
		// return Promise.promise(true)
		// 	.pipe(function(_) {
		// 		return ClientCommands.run(['sleep', '600000'], Constants.DOCKER_IMAGE_DEFAULT)
		// 			.then(function(out) {
		// 				trace('should be job id');
		// 				trace('out=${out}');
		// 				return true;
		// 			});
		// 	});
	}

	// public function testJobMarkedForDeletion()
	// {
	// }

	// public function testJobStatusTimeRunning()
	// {
	// }

	// public function testKillJobs()
	// {
	// }

	// public function testPushDockerImage()
	// {
	// }

	public function new() {}
}