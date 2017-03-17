package storage;

import util.DockerTools;

import utils.TestTools;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;
import js.npm.fsextended.FsExtended;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.CallbackPromise;
import promhx.StreamPromises;
import promhx.deferred.DeferredPromise;

import ccc.storage.ServiceStorage;
import ccc.storage.ServiceStorageLocalFileSystem;

import util.streams.StreamTools;
import util.streams.StdStreams;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;

class TestStorageLocal extends TestStorageBase
{
	var _streams :StdStreams = {out:js.Node.process.stdout, err:js.Node.process.stderr};
	var _testPath :String;

	public function new() {super();}

	@post
	public function postInject()
	{
		_storage = ccc.storage.ServiceStorageLocalFileSystem.getService();
		super.postInject();
	}

	override public function setup() :Null<Promise<Bool>>
	{
		_testPath = '/tmp/storageTest' + Math.floor(Math.random() * 1000000);
		FsExtended.ensureDirSync(_testPath);
		return Promise.promise(true);
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		FsExtended.deleteDirSync(_testPath);
		return Promise.promise(true);
	}

	@timeout(1000)
	public function testStorageLocal()
	{
		var storage = new ServiceStorageLocalFileSystem().setRootPath(_testPath);

		return Promise.promise(true)
			.pipe(function(_) {
				return doServiceStorageTest(storage);
			});
	}
}