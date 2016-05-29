package storage;

import util.DockerTools;

import utils.TestTools;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;
import js.npm.Ssh;
import js.npm.Docker;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.CallbackPromise;
import promhx.StreamPromises;
import promhx.deferred.DeferredPromise;

import ccc.storage.ServiceStorage;

import util.streams.StreamTools;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;

class TestStorageBase extends haxe.unit.async.PromiseTest
{
	function doServiceStorageTest(storage :ServiceStorage) :Promise<Bool>
	{
		var testFileContent1 = 'This is an example: 久有归天愿.';
		var testFilePath1 = 'sftptestfile';

		var testFileContent2 = 'This is another example: 天愿.';
		var testFilePath2 = 'somePath${Math.floor(Math.random() * 1000000)}/sftptestfile2';

		var testdir = 'somedir${Math.floor(Math.random() * 1000000)}/withchild';

		return Promise.promise(true)
			//Write and read a file
			.pipe(function(_) {
				var outputStream = StreamTools.stringToStream(testFileContent1);
				return storage.writeFile(testFilePath1, outputStream);
			})
			.pipe(function(_) {
				return storage.readFile(testFilePath1);
			})
			.pipe(function(readStream) {
				return promhx.StreamPromises.streamToString(readStream);
			})
			.then(function(val) {
				assertEquals(val, testFileContent1);
				return true;
			})
			.pipe(function(_) {
				return storage.listDir(Path.dirname(testFilePath1));
			})
			.then(function(files) {
				assertTrue(files.exists(function(f) return f == Path.basename(testFilePath1)));
				return true;
			})
			//Delete it
			.pipe(function(_) {
				return storage.deleteFile(testFilePath1);
			})
			.pipe(function(_) {
				return storage.listDir(Path.dirname(testFilePath1));
			})
			.then(function(files) {
				assertTrue(!files.exists(function(f) return f == Path.basename(testFilePath1)));
				return true;
			})

			//Write and read a file that has a parent directory
			.pipe(function(_) {
				var outputStream = StreamTools.stringToStream(testFileContent2);
				return storage.writeFile(testFilePath2, outputStream);
			})
			.pipe(function(_) {
				return storage.readFile(testFilePath2);
			})
			.pipe(function(readStream) {
				return promhx.StreamPromises.streamToString(readStream);
			})
			.then(function(val) {
				assertEquals(val, testFileContent2);
				return true;
			})
			//Delete it
			.pipe(function(_) {
				return storage.deleteFile(testFilePath2);
			})
			.pipe(function(_) {
				return storage.listDir(Path.dirname(testFilePath2));
			})
			.then(function(files) {
				assertTrue(!files.exists(function(f) return f == Path.basename(testFilePath2)));
				return true;
			})

			//Create a directory
			//No longer. Directories without files in them are ignored.
			//These are file base files system representations.
			//Empty directories have no meaning

			//Remove the directory
			.pipe(function(_) {
				return storage.makeDir(testdir);
			})
			.pipe(function(_) {
				return storage.deleteDir(testdir);
			})
			.pipe(function(_) {
				return storage.listDir(haxe.io.Path.directory(testdir));
			})
			.then(function(filelist) {
				assertTrue(filelist.length == 0);
				return true;
			})

			.then(function(_) {
				storage.close();
				return true;
			});
	}

	public function new() {}
}