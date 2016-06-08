package storage;

import util.DockerTools;

import utils.TestTools;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;
import js.npm.Ssh;
import js.npm.Docker;
import js.npm.FsExtended;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.CallbackPromise;
import promhx.StreamPromises;
import promhx.DockerPromises;
import promhx.deferred.DeferredPromise;

import ccc.storage.ServiceStorage;
import ccc.storage.StorageTools;
import ccc.storage.StorageDefinition;
import ccc.storage.StorageSourceType;
import ccc.storage.ServiceStorageSftp;
import ccc.compute.ConnectionToolsDocker;
import ccc.compute.workers.WorkerProviderBoot2Docker;
import ccc.compute.execution.DockerJobTools;
import ccc.storage.ServiceStorageLocalFileSystem;

import util.streams.StreamTools;
import util.streams.StdStreams;
import util.SshTools;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;

class TestStorageSftp extends TestStorageBase
{
	var _container :DockerContainer;
	var _sshPort = 2222;
	var _sftpFs :ServiceStorage;

	public function new() {super();}

	override public function setup() :Null<Promise<Bool>>
	{
		var tarStream = js.npm.TarFs.pack('test/res/sshserver');
		var imageId = 'sshserver:latest';
		var labelKey = 'TestSftpStorage';
		var containerLabel = {};
		Reflect.setField(containerLabel, labelKey, '1');

		var ports = [22 => _sshPort];

		var docker;

		return Promise.promise(true)
			.then(function(_) {
				docker = ConnectionToolsDocker.getDocker();
				return true;
			})
			//Check for image
			.pipe(function(_) {
				return DockerPromises.listImages(docker);
			})
			.pipe(function(imageData) {
				var foundImage = imageData.find(function(i) return i.RepoTags.exists(function(s) return s == imageId));
				if (foundImage != null) {
					return Promise.promise(foundImage.Id);
				} else {
					return DockerTools.buildDockerImage(docker, imageId, tarStream, null, Log.log);
				}
			})
			//////////////////////////////////////////
			//Stop, remove, and deleting existing containers
			// Stop and remove existing containers
			.pipe(function(_) {
				//Containers stopped. Now remove
				return DockerPromises.listContainers(docker, {all:true, filters:DockerTools.createLabelFilter(labelKey)})
					.pipe(function(toRemove) {
						return DockerTools.removeAll(docker, toRemove);
					});
			})
			.pipe(function(_) {
				return DockerTools.createContainer(docker, {Image:imageId, Labels: containerLabel}, ports);
			})
			.pipe(function(container) {
				_container = container;
				return DockerTools.startContainer(container, null, ports);
			})
			.thenTrue();
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		if (_sftpFs != null) {
			_sftpFs.close();
			_sftpFs = null;
		}

		if (_container != null) {
			return DockerTools.createContainerDisposer(_container).dispose();
		}

		return Promise.promise(true);
	}

	//TODO: this is way too long!!!
	// There's a problem with the SFTP ServiceStorage
	@timeout(120000)
	public function testSftpStorage()
	{
		return Promise.promise(true)
			.then(function(_) {
				var host :String = ConnectionToolsDocker.getDockerHost();
				var sshConfig :ConnectOptions = {host:host, port:_sshPort, username:'root', password:'screencast'};
				var config :StorageDefinition = {type:StorageSourceType.Sftp, sshConfig:sshConfig, rootPath:'/tmp'};
				_sftpFs = new ServiceStorageSftp()
					.setConfig(config);
				return _sftpFs;
			})
			.pipe(function(storage) {
				return doServiceStorageTest(storage);
			});
	}

	@timeout(120000)
	public function testSshTools()
	{
		return Promise.promise(true)
			.pipe(function(storage) {
				var host :String = ConnectionToolsDocker.getDockerHost();
				var sshConfig :ConnectOptions = {host:host, port:_sshPort, username:'root', password:'screencast'};
				return SshTools.execute(sshConfig, 'find /some/made/up/path -type f', 10, 20)
					.then(function(result) {
						assertEquals(result.code, 1);
						assertTrue(result.stderr != null && result.stderr.trim() == "find: `/some/made/up/path': No such file or directory");
						return true;
					});
			});
	}

	// @timeout(1000)
	// public function testSftpConfiguredCorrectly()
	// {
	// 	return WorkerProviderBoot2Docker.isSftpConfigInLocalDockerMachine()
	// 		.then(function(ok) {
	// 			assertTrue(ok);
	// 			return true;
	// 		});
	// }

	// @timeout(120000)
	// public function testLocalStorageToSftpStorage()
	// {
	// 	var random = js.npm.ShortId.generate();
	// 	var baseFileName = 'tempFile';
	// 	var tempFilePath = '/tmp/some/made/up/dir/$random/$baseFileName';
	// 	var tempFileContent = js.npm.ShortId.generate();
	// 	var targetPath = '/tmp/some/made/up/dir/$random/$baseFileName';

	// 	FsExtended.ensureDirSync(Path.dirname(tempFilePath));
	// 	FsExtended.writeFileSync(tempFilePath, tempFileContent);

	// 	var localStorage = ServiceStorageLocalFileSystem.getServiceWithRoot(Path.dirname(tempFilePath));
	// 	var workerStorage = WorkerProviderBoot2Docker.getWorkerStorage();
	// 	workerStorage = workerStorage.setRootPath(Path.dirname(targetPath));

	// 	return DockerJobTools.copyInternal(localStorage, workerStorage)
	// 		.pipe(function(ok) {
	// 			return workerStorage.readFile(baseFileName)
	// 				.pipe(StreamPromises.streamToString)
	// 				.then(function(s) {
	// 					assertEquals(s, tempFileContent);
	// 					return true;
	// 				});
	// 		});
	// }

	@timeout(120000)
	public function XtestSshStorageMethodsToLocalDockerHost()
	{
		var worker = WorkerProviderBoot2Docker.getLocalDockerWorker();
		var docker = new Docker(worker.docker);
		var sshConfig = worker.ssh;
		var dateString = TestTools.getDateString();
		var hostDirBase = '/tmp/testSshStorageMethodsToLocalDockerHost/$dateString';
		var hostDir = '$hostDirBase/outputs';
		var streams = {out:js.Node.process.stdout, err:js.Node.process.stderr};
		var dataVolumeContainer;
		return Promise.promise(true)
			//Prepare test directory
			.pipe(function(_) {
				return Promise.promise(true)
					.pipe(function(_) {
						return SshTools.execute(sshConfig, 'sudo rm -rf $hostDirBase');
					})
					.pipe(function(result) {
						assertTrue(result.code == 0);
						return SshTools.execute(sshConfig, 'mkdir -p $hostDir');
					})
					.thenTrue();
			})

			//Build and run the test image that writes to the mounted directory
			.pipe(function(_) {
				var path = 'test/res/testSshStorageMethodsToLocalDockerHost/dockerContext';
				var localStorage = StorageTools.getStorage({type:StorageSourceType.Local, rootPath:path});
				var tag = 'testsshlocaldockerhost';
				return localStorage.readDir()
					.pipe(function(stream) {
						return DockerTools.buildDockerImage(docker, tag, stream, null)
							.then(function(imageId) {
								localStorage.close();//Not strictly necessary since it's local, but just always remember to do it
								return imageId;
							});
					})
					.pipe(function(imageId) {
						// Log.info('Running container\n');
						var mounts :Array<Mount> = [
							{
								Source: hostDir,
								Destination: '/outputs',
								Mode: 'rw',//https://docs.docker.com/engine/userguide/dockervolumes/#volume-labels
								RW: true
							}
						];

						var labels :Dynamic<String> = {};
						return DockerJobTools.runDockerContainer(docker, 'fakeComputeJobId', imageId, null, mounts, null, labels, Log.log);
					});
			})
			//Read and confirm data files written in the host directory
			.pipe(function(_) {
				var sftpFs = new ServiceStorageSftp()
					.setConfig({type:StorageSourceType.Sftp, sshConfig:sshConfig, rootPath:hostDir});
				return Promise.promise(true)
					.pipe(function(_) {
						return sftpFs.listDir(hostDir);
					})
					.pipe(function(files) {
						///outputs/output1
						assertTrue(files.has('output1'));
						assertTrue(files.has('output2'));
						return Promise.promise(true)
							.pipe(function(_) {
								return sftpFs.readFile('output1')
									.pipe(function(readstream) {
										return StreamPromises.streamToString(readstream);
									})
									.then(function(content) {
										assertTrue(content.trim() == 'output1content');
										return true;
									});
							})
							.pipe(function(_) {
								return sftpFs.readFile('output2')
									.pipe(function(readstream) {
										return StreamPromises.streamToString(readstream);
									})
									.then(function(content) {
										assertTrue(content.trim() == 'output2content');
										return true;
									});
							});
					});
			});
	}
}