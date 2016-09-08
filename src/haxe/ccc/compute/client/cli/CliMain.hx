package ccc.compute.client.cli;


import haxe.Json;
import haxe.remoting.JsonRpc;
import t9.remoting.jsonrpc.RemoteMethodDefinition;

import js.Node;
import js.node.ChildProcess;
import js.node.Fs;
import js.node.Path;

import js.npm.commander.Commander;

import t9.remoting.jsonrpc.cli.CommanderTools;

using Lambda;

/**
 * CLI for interacted with the platform server and tools
 */
class CliMain
{
	public static function main()
	{
		js.npm.sourcemapsupport.SourceMapSupport;
		ErrorToJson;
		var bunyanLogger = Logger.log;
		untyped bunyanLogger.level(40);

		//Embed various files
		util.EmbedMacros.embedFiles('etc', ["etc/hxml/.*"]);

		var program :Commander = Node.require('commander');
		//Is there a remote server config? If not, the commands will be limited.

		program = program.option('-S, --server <server>', 'Set server host here rather than via configuration');//'localhost:9000'
		program = program.option('-v, --verbose', 'Show the JSON-RPC call to the server');
		program = program.option('-p, --public', 'Use the public server (ccc.bionano.autodesk.com:9000)');
		program = program.option('-c, --check', 'Check server and client version before making remote API call');

		var address = null;
		function printRpcRequest(requestDef) {
			if (Reflect.field(program, "verbose")) {
				Node.console.log('-------JSON-RPCJson-------\n' + Json.stringify(requestDef, null, '\t') + '\n--------------------------');
				if (address != null) {
					Node.console.log('host=$address');
				}
			}
		}

		var isValidCommand = false;

		var context = new t9.remoting.jsonrpc.Context();
		context.rpc.add(function(r) {
			var p :{verbose:Bool} = Node.require('commander');
			if (p.verbose) {
				trace(Json.stringify(r, null, '  '));
			}
		});
		context.registerService(ccc.compute.client.cli.ClientCommands);

		//The following functions are broken out so that the CLI commands can be listed
		//in alphabetical order when the help command is called.
		function serverRequest(requestDef :RequestDef) {
			isValidCommand = true;
			return maybeThrowErrorIfVersionMismatch()
				.pipe(function(_) {
					requestDef.id = JsonRpcConstants.JSONRPC_NULL_ID;//This is not strictly necessary but keep it for completion.
					var hostAndPort = CliTools.getServerHost();
					return Promise.promise(true)
						.pipe(function(_) {
							address = 'http://$hostAndPort${SERVER_RPC_URL}';
							printRpcRequest(requestDef);
							var clientConnection = new t9.remoting.jsonrpc.JsonRpcConnectionHttpPost(address);
							return clientConnection.request(requestDef.method, requestDef.params)
								.then(function(result) {
									var msg = Json.stringify(result, null, '\t');
#if nodejs
									Node.console.log(msg);
#else
									trace(msg);
#end
									Node.process.exit(0);

									return true;
								});
						});
				})
				.catchError(function(err) {
					trace(Json.stringify({error:err}, null, '  '));
					Node.process.exit(1);
				});
		}

		function addServerMethod(serverMethodDefinition :RemoteMethodDefinition) {
			CommanderTools.addCommand(program, serverMethodDefinition, serverRequest);
		}

		function clientRequest(requestDef) {
			isValidCommand = true;
			requestDef.id = JsonRpcConstants.JSONRPC_NULL_ID;//This is not strictly necessary but keep it for completion.
			var command = program.commands.find(function(e) return untyped e._name == requestDef.method);
			return maybeThrowErrorIfVersionMismatch()
				.pipe(function(_) {
					return context.handleRpcRequest(requestDef);
				})
				.then(function(result :ResponseDefSuccess<CLIResult>) {
					if (result.error != null) {
						traceRed('error=${result.error}');
						Node.process.exit(1);
					}
					switch(result.result) {
						case Success:
							Node.process.exit(0);
						case PrintHelp:
							Node.console.log(command.helpInformation());
							Node.process.exit(0);
						case PrintHelpExit1:
							Node.console.log(command.helpInformation());
							Node.process.exit(1);
						case ExitCode(code):
							Node.process.exit(code);
						default:
							Node.console.log('Internal Error: unknown CLIResult: ${result.result}');
							Node.process.exit(-1);
					}
				}).catchError(function(err) {
					traceRed('ERROR from $requestDef\nError:\n${err}');
					Node.process.exit(1);
				});
		}

		function addClientMethod(clientMethodDefinition :RemoteMethodDefinition) {
			CommanderTools.addCommand(program, clientMethodDefinition, clientRequest);
		}

		//Add the client methods. These are handled the same as the remote JsonRpc
		//methods, except that they are local, so the command JsonRpc is just sent
		//to the local context.
		var clientRpcDefinitions = t9.remoting.jsonrpc.Macros.getMethodDefinitions(ccc.compute.client.cli.ClientCommands);

		var rpcDefinitionMap = new Map<String, {isClient:Bool, def:RemoteMethodDefinition}>();
		var rpcAlias :Array<String> = [];
		for (def in clientRpcDefinitions) {
			rpcDefinitionMap.set(def.alias, {isClient:true, def:def});
			rpcAlias.push(def.alias);
		}

		//Server methods
		//ccc.compute.server.ServerCommands, 
		var serverMethodDefinitions = t9.remoting.jsonrpc.Macros.getMethodDefinitions(ccc.compute.ServiceBatchCompute, ccc.compute.server.tests.ServiceTests);
		for (def in serverMethodDefinitions) {
			rpcDefinitionMap.set(def.alias, {isClient:false, def:def});
			rpcAlias.push(def.alias);
		}
		rpcAlias.sort(Reflect.compare);

		for (alias in rpcAlias) {
			var defBlob = rpcDefinitionMap[alias];
			if (defBlob.isClient) {
				addClientMethod(defBlob.def);
			} else {
				addServerMethod(defBlob.def);
			}
		}

		program
			.command('*', {noHelp:true})
			.action(function(arg){
				if (arg == null) {
					program.outputHelp();
				} else {
					traceRed('Unknown command: $arg');
				}
				Node.process.exit(0);
			});

		program.parse(Node.process.argv);
		if (program.args.length == 0) {
			program.outputHelp();
		}
	}

	static function maybeThrowErrorIfVersionMismatch() :Promise<Bool>
	{
		var program :{check:Bool} = Node.require('commander');
		if (program.check) {
			return throwErrorIfVersionMismatch();
		} else {
			return Promise.promise(true);
		}
	}

	static function throwErrorIfVersionMismatch() :Promise<Bool>
	{
		return ClientCommands.validateServerAndClientVersions()
			.then(function(ok) {
				if (!ok) {
					traceRed('Client and server version mismatch');
					Node.process.exit(1);
				}
				return ok;
			});
	}

}