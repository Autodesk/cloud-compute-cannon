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
		var tmpFile = '/tmp/tempFileDump';
		var s = 'StringToStream';
		var fileStream = StreamTools.stringToStream(s);
		var writable = Fs.createWriteStream(tmpFile);

		return StreamPromises.pipe(fileStream, writable)
			.then(function(_) {
				var result = Fs.readFileSync(tmpFile, {encoding:'utf8'});
				assertEquals(result, s);
				return true;
			});
	}
}