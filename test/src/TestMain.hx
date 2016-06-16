import js.Node;
import js.node.child_process.ChildProcess;

import haxe.unit.async.PromiseTestRunner;

import ccc.compute.InitConfigTools;

using Lambda;
using StringTools;

class TestMain
{
	public static function setupTestExecutable()
	{
		var bunyanLogger :js.npm.Bunyan.BunyanLogger = Logger.log;
		bunyanLogger.level(js.npm.Bunyan.WARN);

		//Required for source mapping
		js.npm.SourceMapSupport;
		util.EmbedMacros.embedFiles('etc');
		ErrorToJson;

		//Prevents warning messages since we have a lot of streams piping to the stdout/err streams.
		js.Node.process.stdout.setMaxListeners(20);
		js.Node.process.stderr.setMaxListeners(20);
	}
}