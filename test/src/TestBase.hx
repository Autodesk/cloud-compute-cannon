package;

import promhx.Promise;

class TestBase extends haxe.unit.async.PromiseTest
{
	var _streams :util.streams.StdStreams = {out:js.Node.process.stdout, err:js.Node.process.stderr};
	var _injector :minject.Injector;

	override public function tearDown() :Null<Promise<Bool>>
	{
		_injector = null;
		return Promise.promise(true);
	}
}