package ccc.compute.test.tests;

class TestStorageLocal extends TestStorageBase
{
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

	public function new() { super(); }
}