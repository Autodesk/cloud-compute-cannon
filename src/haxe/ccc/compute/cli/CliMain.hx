package ccc.compute.cli;

import ccc.compute.Definitions;
import ccc.compute.Definitions.Constants.*;

import haxe.Json;
import haxe.remoting.JsonRpc;

import js.Node;
import js.node.ChildProcess;
import js.node.Fs;
import js.node.Path;

import js.npm.Commander;

import t9.remoting.jsonrpc.cli.CommanderTools;

using Lambda;

/**
 * CLI for interacted with the platform server and tools
 */
class CliMain
{
	public static function main2()
	{
		var docker = new js.npm.Docker(null);

		promhx.Promise.whenAll(
			[
				util.DockerTools.ensureContainer(docker, 'redis:3', 'name', 'redis'),
				util.DockerTools.ensureContainer(docker, 'registry:2', 'name', 'registry', null, [ccc.compute.Definitions.Constants.REGISTRY_DEFAULT_PORT=>5000])
			])
		.then(function(_) {
			trace('done');
		});

		js.Node.setTimeout(function() {}, 3000);
	}

	public static function main()
	{
		js.npm.SourceMapSupport;
		ErrorToJson;

		//Embed various files
		util.EmbedMacros.embedFiles('etc');

		var program :Commander = js.Node.require('commander');
		//Is there a remote server config? If not, the commands will be limited.

		program = program.option('-H, --host <host>', 'Set server host here rather than via configuration');//'localhost:9000'
		program = program.option('-v, --verbose', 'Show the JSON-RPC call to the server');

		var address = null;
		function printRpcRequest(requestDef) {
			if (Reflect.field(program, "verbose")) {
				js.Node.console.log('-------JSON-RPCJson-------\n' + Json.stringify(requestDef, null, '\t') + '\n--------------------------');
				if (address != null) {
					js.Node.console.log('host=$address');
				}
			}
		}

		//Add the client methods. These are handled the same as the remote JsonRpc
		//methods, except that they are local, so the command JsonRpc is just sent
		//to the local context.
		var context = new t9.remoting.jsonrpc.Context();
		context.registerService(ccc.compute.cli.ClientCommands);
		var clientRpcDefinitions = t9.remoting.jsonrpc.Macros.getMethodDefinitions(ccc.compute.cli.ClientCommands);
		// trace('clientRpcDefinitions=${clientRpcDefinitions}');
		var clientMethods :Set<String> = Set.createString(clientRpcDefinitions.map(function(d) return d.alias));
		CommanderTools.addCommands(program, clientRpcDefinitions, function(requestDef) {
			requestDef.id = JsonRpcConstants.JSONRPC_NULL_ID;//This is not strictly necessary but keep it for completion.
			printRpcRequest(requestDef);
			// trace('program.commands=${program.commands}');
			var command = program.commands.find(function(e) return untyped e._name == requestDef.method);
			// trace('command=${command}');
			// trace(untyped program.commands[0]._name);
			context.handleRpcRequest(requestDef)
				.then(function(result :ResponseDefSuccess<CLIResult>) {
					if (result.error != null) {
						trace(result.error);
					}
					switch(result.result) {
						case Success:
							Node.process.exit(0);
						case PrintHelp:
							js.Node.console.log(command.helpInformation());
							Node.process.exit(0);
						case PrintHelpExit1:
							js.Node.console.log(command.helpInformation());
							Node.process.exit(1);
						case ExitCode(code):
							Node.process.exit(code);
						default:
							js.Node.console.log('Internal Error: unknown CLIResult: ${result.result}');
							Node.process.exit(-1);
					}
				}).catchError(function(err) {
					Log.error('ERROR from $requestDef\nError:\n$err');
					js.Node.process.exit(1);
				});
		});

		//The actual remote server method definitions
		var serverMethodDefinitions = t9.remoting.jsonrpc.Macros.getMethodDefinitions(ccc.compute.server.ServerCommands, ccc.compute.ServiceBatchCompute);
		serverMethodDefinitions = serverMethodDefinitions.filter(function(d) {
			return !clientMethods.has(d.alias);
		});
		CommanderTools.addCommands(program, serverMethodDefinitions, function(requestDef) {
			requestDef.id = JsonRpcConstants.JSONRPC_NULL_ID;//This is not strictly necessary but keep it for completion.
			CliTools.getServerHost()
				.then(function(hostport) {
					address = 'http://$hostport${SERVER_RPC_URL}';
					printRpcRequest(requestDef);
					var clientConnection = new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(address);
					clientConnection.request(requestDef.method, requestDef.params)
						.then(function(result) {
							var msg = Json.stringify(result, null, '\t');
#if nodejs
							js.Node.console.log(msg);
#else
							trace(msg);
#end
							js.Node.process.exit(0);
						});
				})
				.catchError(function(err) {
					trace('ERROR from $requestDef\nError:\n$err');
					js.Node.process.exit(1);
				});
		});

		program
			.command('*')
			.description('output usage information')
			.action(function(env){
				// trace('program.host=${untyped program.host}');
				if (js.Node.process.argv[2] != null) {
					js.Node.console.log('\n  ERROR: Unknown command: ' + js.Node.process.argv[2]);
				}
				program.outputHelp();
				js.Node.process.exit(0);
			});

		if (js.Node.process.argv.slice(2).length == 0) {
			// trace('FORCE HELP');
			program.outputHelp();
		} else {
			//Long timeout so the process doesn't end automatically,
			//since active Promises on the Promise stack do not prevent
			//the node.js process from exiting.
			js.Node.setTimeout(function(){trace('ERROR EXITED BECAUSE TIMED OUT, should not exit this way');}, 10000000);
			program.parse(js.Node.process.argv);
		}
	}

}