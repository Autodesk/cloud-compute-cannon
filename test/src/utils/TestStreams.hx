package utils;

import js.node.Fs;

import promhx.StreamPromises;

import util.streams.StreamTools;

class TestStreams extends haxe.unit.async.PromiseTest
{
	public function new() {}

	@timeout(100)
	public function testStreamTools()
	{
		var s = 'StringToStream';
		var fileStream = StreamTools.stringToStream(s);

		var writable = Fs.createWriteStream('/tmp/tempFileDump');

		return StreamPromises.pipe(fileStream, writable);
	}
}