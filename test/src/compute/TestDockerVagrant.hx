package compute;

import haxe.Json;

import js.Node;
import js.node.Http;
import js.node.Path;
import js.node.Fs;
import js.npm.Docker;
import js.npm.FsExtended;
import js.npm.FsPromises;
import js.npm.RedisClient;
import js.npm.HttpPromises;
import js.npm.Ssh;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.CallbackPromise;
import promhx.deferred.DeferredPromise;

import ccc.storage.ServiceStorage;
import ccc.storage.ServiceStorageLocalFileSystem;
import ccc.storage.StorageRestApi;
import ccc.compute.ComputeQueue;
import ccc.compute.ServiceBatchCompute;
import ccc.compute.ComputeTools;
import ccc.compute.execution.DockerJobTools;
import ccc.compute.workers.VagrantTools;
import ccc.compute.workers.WorkerProviderVagrantTools;
import ccc.compute.workers.WorkerProviderBoot2Docker;

import util.RedisTools;
import util.SshTools;
import util.DockerTools;
import util.streams.StreamTools;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;
using ccc.compute.workers.WorkerTools;

class TestDockerVagrant extends TestComputeBase
{
	public static var ROOT_PATH = 'tmp/TestDockerCompute/';
	static var IMAGE_ID = 'testimage';
	var _address :String = '192.168.88.10';
	var _machinePath :String;

	public function new()
	{
		_machinePath = ROOT_PATH + _address.replace('.', '_');
	}

	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				return WorkerProviderVagrantTools.ensureWorkerBox(_machinePath, _address, _streams)
					.thenTrue();
			});
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		return super.tearDown()
			.pipe(function(_) {
				return VagrantTools.shutdown(_machinePath, _streams);
			});
	}

	@timeout(120000)
	public function XXtestSshAndDockerConnectivity()
	{
		var workerDef;
		var ssh;
		return Promise.promise(true)
			.pipe(function(_) {
				return WorkerProviderVagrantTools.getWorkerDefinition(_machinePath, _streams);
			})
			.pipe(function(out) {
				workerDef = out;
				return SshTools.getSsh(workerDef.ssh);
			})
			.pipe(function(client :SshClient) {
				ssh = client;
				return SshTools.execute(client, 'echo "Hello"');
			})
			.then(function(result) {
				assertEquals('Hello', result.stdout.trim());
				ssh.end();
				return true;
			})
			.pipe(function(_) {
				var opts = cast(Reflect.copy(workerDef.docker) : ConstructorOpts);
				opts.protocol = 'http';
				var docker = new Docker(opts);
				var promise = new promhx.CallbackPromise();
				docker.info(promise.cb2);
				return promise;
			})
			.then(function(info :DockerInfo) {
				assertNotNull(Reflect.field(info, 'ID'));
				assertNotNull(Reflect.field(info, 'Containers'));
				return true;
			})
			.pipe(function(_) {
				var docker = workerDef.getInstance().docker();
				var promise = new promhx.CallbackPromise();
				docker.info(promise.cb2);
				return promise;
			})
			.then(function(info :DockerInfo) {
				assertNotNull(Reflect.field(info, 'ID'));
				assertNotNull(Reflect.field(info, 'Containers'));
				return true;
			})
			.errorPipe(function(err) {
				Log.error(err);
				Log.error('Is the docker protocol set correctly? (http vs https)');
				throw err;
			})
			.thenTrue();
	}

	@timeout(120000)
	public function XXtestBuildDockerJob()
	{
		var tarStream = js.npm.TarFs.pack('server/compute/test/res/testDockerImage1');

		var workerDef;
		var ssh;
		return Promise.promise(true)
			.pipe(function(_) {
				return WorkerProviderVagrantTools.getWorkerDefinition(_machinePath, _streams);
			})
			.pipe(function(out) {
				workerDef = out;
				var docker = workerDef.getInstance().docker();
				return DockerTools.buildDockerImage(docker, IMAGE_ID, tarStream, _streams);
			})
			// .pipeF(DockerJobTools.getDockerResultStream)
			.thenTrue();
	}

	@timeout(120000)
	public function XXtestRunDockerJob()
	{
		return Promise.promise(true)
			.pipe(function(_) {
				return WorkerProviderVagrantTools.getWorkerDefinition(_machinePath, _streams);
			})
			.pipe(function(workerDef) {
				var docker = workerDef.getInstance().docker();
				var deferred = new DeferredPromise();
				docker.createContainer({
					Image: IMAGE_ID,
					AttachStdout: true,
					AttachStderr: true,
					Tty: false,
				}, function(err, container) {
					if (err != null) {
						deferred.boundPromise.reject(err);
						return;
					}

					container.attach({ logs:true, stream:true, stdout:true, stderr:true}, function(err, stream) {
						if (err != null) {
							deferred.boundPromise.reject(err);
							return;
						}
						untyped __js__('container.modem.demuxStream(stream, process.stdout, process.stdout)');
						container.start(function(err, data) {
							if (err != null) {
								deferred.boundPromise.reject(err);
								return;
							}
						});
						stream.once('end', function() {
							deferred.resolve(true);
						});
					});
				});
				return deferred.boundPromise;
			})
			.thenTrue();
	}

	@timeout(120000)
	public function XXtestDockerCopyInputs()
	{
		//The files to copy
		var testPath = '/tmp/storageTest' + Math.floor(Math.random() * 100000000) + '/';
		FsExtended.createDirSync(testPath);
		var filePath1 = Path.join(testPath, 'testFile1');
		var filePath2 = Path.join(testPath, 'testFile2');
		var testFiles = [filePath1 => 'testFile1Content', filePath2 => 'testFile2Content'];
		for (f in testFiles.keys()) {
			Fs.writeFileSync(f, testFiles[f]);
		}

		var server;
		var ssh;
		var sftp;

		var workerDef;
		var ssh;
		return Promise.promise(true)
			.pipe(function(_) {
				return WorkerProviderVagrantTools.getWorkerDefinition(_machinePath, _streams);
			})
			.pipe(function(out) {
				workerDef = out;
				return workerDef.getInstance().ssh();
			})
			.pipe(function(connectedSsh :js.npm.Ssh.SshClient) {
				ssh = connectedSsh;
				return SshTools.execute(ssh, 'mkdir -p "$testPath"');
			})
			.pipe(function(sshResult) {
				return SshTools.sftp(ssh);
			})
			.pipe(function(sftpResult) {
				sftp = sftpResult;
				//Create stream from file
				var fileStream = Fs.createReadStream(filePath1);
				return SshTools.writeStream(sftp, fileStream, filePath1);
			})
			.pipe(function(_) {
				//Create stream from string
				var fileStream = StreamTools.stringToStream(testFiles[filePath2]);
				return SshTools.writeStream(sftp, fileStream, filePath2);
			})
			.pipe(function(sshResult) {
				var p = new CallbackPromise();
				sftp.readdir(Path.dirname(filePath1), p.cb2);
				return p;
			})
			//Make sure both files are on the remote file system
			.then(function(fileList :Array<{filename:String}>) {
				return fileList.exists(function(e) return e.filename == filePath1) && fileList.exists(function(e) return e.filename == filePath2);
			})
			.thenTrue();
	}
}