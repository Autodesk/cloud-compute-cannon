package ccc.compute.server.tests;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.CallbackPromise;
import promhx.StreamPromises;
import promhx.deferred.DeferredPromise;

import ccc.storage.ServiceStorage;
import ccc.storage.ServiceStorageBase;

import util.streams.StreamTools;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;

class TestStorageBase extends haxe.unit.async.PromiseTest
{
	public var _storage :ServiceStorage;

	public function new(?storage :ServiceStorage)
	{
		if (storage != null) {
			_storage = storage;
			var date = DateTools.format(Date.now(), '%Y%m%d-%H%M%S');
			_storage = _storage.appendToRootPath('tests/$date');
		}
	}

	@timeout(1200000)
	public function testFileExists() :Promise<Bool>
	{
		return _storage.exists('sdfsdfafsadfasdcfsfcasfsadf')
			.then(function(exists) {
				assertFalse(exists);
				return true;
			})
			.errorPipe(function(err) {
				assertIsNull(err);
				return Promise.promise(false);
			});
	}

	@timeout(120000)
	public function testGettingFileThatDoesNotExist() :Promise<Bool>
	{
		return _storage.readFile('sdfsdfafsadfasdcfsfcasfsadf')
			.then(function(_) {
				assertTrue(false);
				return true;
			})
			.errorPipe(function(err) {
				return Promise.promise(true);
			});
	}

	function doPathParsing(s :ServiceStorage) :Promise<Bool>
	{
		var rootPath = 'rootPathTest/';
		var storage :ServiceStorageBase = cast s.clone();

		storage.setRootPath(rootPath);

		var filePath = 'some/file/path';

		assertEquals(storage.getPath(filePath), '${storage.getRootPath()}${filePath}');

		return Promise.promise(true);
	}

	function doStorageTest(storage :ServiceStorage) :Promise<Bool>
	{
		Assert.notNull(storage);
		var testFileContent1 = 'This is an example: 久有归天愿.${Math.floor(Math.random() * 1000000)}';
		var testFilePath1 = 'tests/storage_test_file';

		var testFileContent2 = 'This is another example: 天愿.${Math.floor(Math.random() * 1000000)}';
		var testFilePath2 = 'tests/somePath${Math.floor(Math.random() * 1000000)}/storage_testfile2';

		var testdir = 'tests/somedir${Math.floor(Math.random() * 1000000)}/withchild';

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
			.pipe(function(val) {
				assertEquals(val, testFileContent1);
				//Also test .exists(filename)
				return storage.exists(testFilePath1)
					.then(function(exists) {
						assertTrue(exists);
						return true;
					});
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


			//Test copying the storage object, appending paths, checking
			//if the objects are stored correctly
			//Also check listDir after appending paths
			.pipe(function(_) {
				var pathToken1 = 'fooPathToken${Math.floor(Math.random() * 1000000)}';
				var filePathFoo = 'fooFile${Math.floor(Math.random() * 1000000)}';
				var fileContentFoo = 'fooFileContent${Math.floor(Math.random() * 1000000)}';

				var storage2 = storage.appendToRootPath(pathToken1);
				assertEquals('${storage.getRootPath()}$pathToken1/', storage2.getRootPath());
				return storage2.writeFile(filePathFoo, StreamTools.stringToStream(fileContentFoo))
					.pipe(function(_) {
						return storage.readFile('${pathToken1}/${filePathFoo}')
							.pipe(function(readStream) {
								return promhx.StreamPromises.streamToString(readStream);
							})
							.then(function(out) {
								assertEquals(fileContentFoo, out);
								return true;
							})
							.pipe(function(_) {
								return storage2.listDir()
									.pipe(function(list1) {
										return storage.listDir(pathToken1)
											.then(function(list2) {
												assertEquals(list1.length, list2.length);
												assertEquals(list1[0], list2[0]);
												return true;
											});
									});
							});
					});
			})
			.then(function(_) {
				storage.close();
				return true;
			});
	}
}