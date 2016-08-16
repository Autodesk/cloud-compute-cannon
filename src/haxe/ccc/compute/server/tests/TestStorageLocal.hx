package ccc.compute.server.tests;

class TestStorageLocal extends TestStorageBase
{
	public function new(?storage :ccc.storage.ServiceStorageLocalFileSystem)
	{
		super(storage);
	}

	@timeout(1000)
	public function testPathsLocal() :Promise<Bool>
	{
		return doPathParsing(_storage);
	}

	@timeout(30000)
	public function testStorageTestLocal() :Promise<Bool>
	{
		return doStorageTest(_storage);
	}
}