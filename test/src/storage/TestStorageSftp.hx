package storage;

import util.DockerTools;

import utils.TestTools;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;
import js.npm.ssh2.Ssh;
import js.npm.docker.Docker;
import js.npm.fsextended.FsExtended;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.CallbackPromise;
import promhx.StreamPromises;
import promhx.DockerPromises;
import promhx.deferred.DeferredPromise;

import ccc.storage.ServiceStorage;
import ccc.storage.StorageTools;
import ccc.storage.StorageSourceType;
import ccc.storage.ServiceStorageSftp;
import ccc.compute.server.ConnectionToolsDocker;
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

class TestStorageSftp extends ccc.compute.server.tests.TestStorageBase
{
	var _container :DockerContainer;
	var _sshPort = 2222;
	var _sftpFs :ServiceStorage;

	public function new() {super();}

	override public function setup() :Null<Promise<Bool>>
	{
		var tarStream = js.npm.tarfs.TarFs.pack('test/res/sshserver');
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
				// trace('list images');
				return DockerPromises.hasImage(docker, imageId)
					.pipe(function(foundImage) {
					if (foundImage) {
						return Promise.promise(imageId);
					} else {
						return DockerTools.buildDockerImage(docker, imageId, tarStream, null, Log.log);
					}
				});
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

	@timeout(120000)
	public function testSftpStorage()
	{
		return Promise.promise(true)
			.then(function(_) {
				var host :String = ConnectionToolsDocker.getDockerHost();
				var config = {type:StorageSourceType.Sftp, credentials:{host:host, port:_sshPort, username:'root', password:'screencast'}, rootPath:'/tmp'};
				_sftpFs = new ServiceStorageSftp()
					.setConfig(config);
				return _sftpFs;
			})
			.pipe(function(storage) {
				return doStorageTest(storage);
			});
	}

	@timeout(120000)
	public function testSshTools()
	{
		return Promise.promise(true)
			.pipe(function(storage) {
				var host :String = ConnectionToolsDocker.getDockerHost();
				var sshConfig = {host:host, port:_sshPort, username:'root', password:'screencast'};
				return SshTools.execute(sshConfig, 'find /some/made/up/path -type f', 10, 20)
					.then(function(result) {
						assertEquals(result.code, 1);
						assertTrue(result.stderr != null && result.stderr.trim() == "find: `/some/made/up/path': No such file or directory");
						return true;
					});
			});
	}
}