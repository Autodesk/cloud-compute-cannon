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
		ccc.compute.workers.WorkerProviderBoot2Docker.setHostWorkerDirectoryMount();
		trace('$ENV_LOG_LEVEL=${Reflect.field(Node.process.env, ENV_LOG_LEVEL)}');
		if (Reflect.hasField(Node.process.env, ENV_LOG_LEVEL)) {
			Logger.log.level(Std.int(Reflect.field(Node.process.env, ENV_LOG_LEVEL)));
		} else {
			Logger.log.level(js.npm.Bunyan.WARN);
		}
		trace('Log.level=${Logger.log.level()}');

		//Required for source mapping
		js.npm.SourceMapSupport;
		util.EmbedMacros.embedFiles('etc');
		ErrorToJson;

		//Prevents warning messages since we have a lot of streams piping to the stdout/err streams.
		js.Node.process.stdout.setMaxListeners(20);
		js.Node.process.stderr.setMaxListeners(20);
	}
}