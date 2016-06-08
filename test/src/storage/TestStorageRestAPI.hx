package storage;

import utils.TestTools;

import haxe.Json;
import haxe.unit.async.PromiseTest;

import js.Node;
import js.node.Path;
import js.node.Fs;
import js.node.Http;
import js.npm.FsPromises;
import js.npm.FsExtended;
import js.npm.RedisClient;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.RequestPromises;

import util.RedisTools;
import ccc.storage.ServiceStorage;
import ccc.storage.ServiceStorageLocalFileSystem;
import ccc.storage.StorageRestApi;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;

class TestStorageRestAPI extends haxe.unit.async.PromiseTest
{
	public function new() {}

	@timeout(2000)
	public function testRestApi()
	{
		var testPath = '/tmp/storageTest' + Math.floor(Math.random() * 1000000);
		var testFile = 'testfile';
		var testFilePath = testPath + '/' + testFile;
		var port = 8999;
		var apiPath = '/testapi/';
		var fileContent1 = 'This is the contents of the file 的私は学生です';
		var fileContent2 = 'boopdepoop';

		FsExtended.createDirSync(testPath);

		var storageService :ServiceStorage = new ServiceStorageLocalFileSystem().setRootPath(testPath);

		var app;
		var server;
		return TestTools.createServer(port)
			.pipe(function(result :ServerCreationStuff) {
				app = result.app;
				server = result.server;
				app.use(apiPath, StorageRestApi.router(storageService));
				return FsPromises.writeFile(fileContent1, testFilePath);
			})
			.pipe(function(_) {
				//Test reading
				var url = 'http://localhost:' + port + apiPath + testFile;
				return RequestPromises.get(url);
			})
			.pipe(function(body) {
				assertEquals(body, fileContent1);
				//Test writing
				var url = 'http://localhost:' + port + apiPath + testFile;
				return RequestPromises.post(url, fileContent2);
			})
			.pipe(function(response) {
				return FsPromises.readFile(testFilePath);
			})
			.pipe(function(fileContent) {
				assertEquals(fileContent, fileContent2);
				return Promise.promise(true);
			})
			.then(function(_) {
				server.close();
				FsExtended.deleteDirSync(testPath);
				return true;
			})
			.thenTrue();
	}
}