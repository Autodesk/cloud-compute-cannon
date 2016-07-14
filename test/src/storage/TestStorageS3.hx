package storage;

import ccc.compute.InitConfigTools;
import ccc.storage.ServiceStorage;
import ccc.storage.ServiceStorageBase;
import ccc.storage.StorageDefinition;
import ccc.storage.StorageSourceType;
import ccc.storage.ServiceStorageS3;
import ccc.storage.StorageTools;

import js.npm.PkgCloud;

import promhx.RequestPromises;

import util.streams.StreamTools;

using Lambda;

class TestStorageS3 extends ccc.compute.server.tests.TestServiceStorage
{
	static var ENV_TEST_S3_KEYID = 'TEST_S3_KEYID';
	static var ENV_TEST_S3_KEY = 'TEST_S3_KEY';
	static var ENV_TEST_S3_REGION = 'TEST_S3_REGION';
	static var ENV_TEST_S3_BUCKET = 'bionano-platform-test';

	// private var storageService :ServiceStorage;

	// creds for an IAM user with only privs to one s3 bucket
	private static var creds :ClientOptionsAmazon = {
		provider: ProviderType.amazon,
		keyId: "AKIAI4NNF7OL75IAUYNA",
		key: "Tf5+pDjoyifh7UVvAI/W9FrZorpWkkgAgAL+gseN",
		region: "us-west-1"
	};

	public function new()
	{
		var storageConfig :StorageDefinition = {
			type: StorageSourceType.Cloud,
			credentials: creds,
			rootPath: "/",
			container: "bionano-platform-test",
			httpAccessUrl: "https://s3-us-west-1.amazonaws.com"
		};
		super(StorageTools.getStorage(storageConfig));
	}

	override public function setup() :Null<Promise<Bool>>
	{
		//setup a bucket for testing?
		return null;
	}

	override public function tearDown() :Null<Promise<Bool>>
	{
		//tear down a bucket?
		return null;
	}

	@timeout(30000)
	override public function testStorage() :Promise<Bool>
	{
		return doServiceStorageTest(_storage);
	}

	@timeout(30000)
	public function testS3ListDir() :Promise<Bool>
	{
		return _storage.listDir()
			.pipe(function(files) {
				Assert.notNull(files);
				return Promise.promise(true);
			});
	}

	@timeout(30000)
	public function XtestS3WriteFile() :Promise<Bool>
	{
		var storageService = _storage;
		var rand = Std.int(Math.random() * 1000000);
		var testFileContent = 'This is an example: 久有归天愿. $rand';
		var testFilePath = 'testfile-autogen-$rand.txt';

		return Promise.promise(true)
			.pipe(function (_) {
				var outputStream = StreamTools.stringToStream(testFileContent);
				return storageService.writeFile(testFilePath, outputStream);
			})
			.pipe(function (_) {
				return storageService.listDir(testFilePath);
			})
			.then(function(files) {
				Assert.that(files.exists(function(f) return f == testFilePath));
				return true;
			})
			.pipe(function (_) {
				return storageService.deleteFile(testFilePath);
			})
			.pipe(function (_) {
				return storageService.listDir(testFilePath);
			})
			.then(function(files) {
				Assert.that(! files.exists(function(f) return f == testFilePath));
				return true;
			});
	}

	// @timeout(30000)
	// public function testStorage() :Promise<Bool>
	// {
	// 	return this.doServiceStorageTest(storageService);
	// }

	function XtestHttpUrl() :Promise<Bool>
	{
		var testPath :String = "file0.csv.gz";
		var httpUrl :String = "https://s3-us-west-1.amazonaws.com/bionano-platform-test/file0.csv.gz";
		_storage.setRootPath('/');
		var serviceStorageS3 :ServiceStorageS3 = cast _storage;

		return Promise.promise(true)
			.then(function (_) {
				Assert.that(serviceStorageS3.getExternalUrl(testPath) == httpUrl);
				return true;
			});
	}

	function XtestStorageDefinitionFromServiceConfiguration() :Promise<Bool>
	{
		var configFilePath = 'server/servers/etc/serverconfig.amazon.s3.template.yaml';
		var config = InitConfigTools.getConfig(configFilePath);
		var storageDefinition = config.server.storage;//ServiceStorageS3.getS3ConfigFromServiceConfiguration(serviceConfiguration);
		return Promise.promise(true)
			.then(function (_) {
				Assert.notNull(storageDefinition);
				return true;
			});
	}

	@timeout(30000)
	public function XtestS3CopyFile() :Promise<Bool>
	{
		var testFileContent = 'This is an example: 久有归天愿.';
		var testFilePath = "testfile-autogen.txt";

		var copyFilePath = "testfile-autogen-copy.txt";

		var baseStorage :ServiceStorageBase = cast _storage;

		return Promise.promise(true)
			.pipe(function (_) {
				return baseStorage.listDir()
					.then(function(files) {
						trace('files=${files}');
						return true;
					});
			})
			.pipe(function (_) {
				var outputStream = StreamTools.stringToStream(testFileContent);
				return baseStorage.writeFile(testFilePath, outputStream);
			})
			.pipe(function (_) {
				return baseStorage.listDir();
			})
			.then(function(files) {
				Assert.that(files.exists(function(f) return f == testFilePath));
				return true;
			})
			.pipe(function (_) {
				return baseStorage.copyFile(testFilePath, copyFilePath);
			})
			.pipe(function (_) {
				return baseStorage.listDir(copyFilePath);
			})
			.then(function(files) {
				Assert.that(files.exists(function(f) return f == copyFilePath));
				return true;
			})
			.pipe(function (_) {
				return baseStorage.deleteFile(testFilePath);
			})
			.pipe(function (_) {
				return baseStorage.deleteFile(copyFilePath);
			})
			.pipe(function (_) {
				return baseStorage.listDir("testfile-autogen");
			})
			.then(function (files) {
				Assert.that(files.length == 0);
				return true;
			});
	}

	@timeout(30000)
	public function XtestS3HttpAccess() :Promise<Bool>
	{
		var testFileContent = 'This is an example for HTTP access: 久有归天愿.';
		var testFilePath = "testfile-http-access.txt";

		var s3Storage :ServiceStorageS3 = cast _storage;
		return Promise.promise(true)
			.pipe(function (_) {
				var outputStream = StreamTools.stringToStream(testFileContent);
				return s3Storage.writeFile(testFilePath, outputStream);
			})
			.pipe(function (_) {
				var httpAccessUrl = s3Storage.getExternalUrl(testFilePath);
				return RequestPromises.get(httpAccessUrl);
			})
			.then(function (content :String) {
				Assert.notNull(content);
				Assert.that(content == testFileContent);
				return true;
			})
			.pipe(function (_){
				return s3Storage.deleteFile(testFilePath);
			})
			.pipe(function (_) {
				return s3Storage.listDir(testFilePath);
			})
			.then(function(files) {
				Assert.that(! files.exists(function(f) return f == testFilePath));
				return true;
			});
	}
}