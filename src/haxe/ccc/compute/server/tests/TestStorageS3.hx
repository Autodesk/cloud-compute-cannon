package ccc.compute.server.tests;

class TestStorageS3 extends TestStorageBase
{
	public function new(?storage :ccc.storage.ServiceStorageS3)
	{
		super(storage);
	}

	@timeout(1000)
	public function testPathsS3() :Promise<Bool>
	{
		return doPathParsing(new ccc.storage.ServiceStorageS3().setConfig(
			{
				type: ccc.storage.StorageSourceType.Cloud,
				container: 'somecontainer',
				rootPath: null,
				httpAccessUrl: 'http://foobar',
				credentials: {
					provider: "amazon",
					keyId: "AKIA",
					key: "F5yk",
					region: "us-west-1"
				}
			}));
	}

	// AWS S3 allows path-like object names
	// @timeout(100)
	// function TODO_CHECK_THIS_testPathConversion() :Promise<Bool>
	// {
	// 	var storageService = new ccc.storage.ServiceStorageS3().setConfig(
	// 		{
	// 			type: ccc.storage.StorageSourceType.Cloud,
	// 			container: 'somecontainer',
	// 			rootPath: null,
	// 			httpAccessUrl: 'http://foobar',
	// 			credentials: {
	// 				provider: "amazon",
	// 				keyId: "AKIA",
	// 				key: "F5yk",
	// 				region: "us-west-1"
	// 			}
	// 		});

	// 	var testPath0 :String = "molecule0/dataset0/file0.csv.gz";
	// 	var convertedTestPath0 :String = "foo/bar/good/molecule0/dataset0/file0.csv.gz";

	// 	return Promise.promise(true)
	// 		.then(function (_) {
	// 			Assert.that(storageService.getRootPath() == "/");
	// 			storageService.appendToRootPath("foo");
	// 			Assert.that(storageService.getRootPath() == "/foo/");
	// 			storageService.appendToRootPath("bar/");
	// 			Assert.that(storageService.getRootPath() == "/foo/bar/");
	// 			storageService.appendToRootPath("//good//");
	// 			Assert.that(storageService.getRootPath() == "/foo/bar/good/");

	// 			var storageServiceS3 :ServiceStorageS3 = cast storageService;
	// 			Assert.that(storageServiceS3.convertPath(testPath0) == convertedTestPath0);
	// 			return true;
	// 		});
	// }

	@timeout(100)
	public function testCloudPathParsingExternalUrl() :Promise<Bool>
	{
		var config = {
			type: ccc.storage.StorageSourceType.Cloud,
			container: 'somecontainer',
			rootPath: null,
			httpAccessUrl: 'http://foobar',
			credentials: {
				provider: "amazon",
				keyId: "AKIA",
				key: "F5yk",
				region: "us-west-1"
			}
		};
		var s = new ccc.storage.ServiceStorageS3().setConfig(config);

		var rootPath = 'rootPathTest';
		var storage :ccc.storage.ServiceStorageBase = cast s.clone();

		storage.setRootPath(rootPath);

		var filePath = 'some/file/path';

		assertEquals(storage.getPath(filePath), '${storage.getRootPath()}${filePath}');
		assertEquals(storage.getExternalUrl(filePath), '${config.httpAccessUrl}/${rootPath}/${filePath}');

		return Promise.promise(true);
	}

	@timeout(30000)
	public function testStorageTestS3() :Promise<Bool>
	{
		if (_storage != null) {
			return doStorageTest(_storage);
		} else {
			return Promise.promise(true);
		}
	}
}