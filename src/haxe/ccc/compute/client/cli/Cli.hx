package ccc.compute.client.cli;

import haxe.Json;

import js.Node;
import js.node.ChildProcess;
import js.node.Fs;
import js.node.Path;

import js.npm.commander.Commander;
import js.npm.RedisClient;

import promhx.Promise;

import batcher.servers.compute.ClientCompute;
import ccc.compute.server.ComputeQueue;
import ccc.compute.server.InstancePool;
import ccc.compute.workers.VagrantTools;
import ccc.compute.server.InitConfigTools;
import ccc.compute.server.ConnectionToolsDocker;
import ccc.compute.server.ServiceBatchCompute;

import util.streams.StdStreams;

using promhx.PromiseTools;

@:enum
abstract VagrantCommand(String) {
	var DestroyAll = 'destroyall';
	var DestroyTestMachines = 'destroytestmachines';
}

@:enum
abstract RedisCommand(String) {
	var Dump = 'dump';
	var AvailableCpus = 'cpus';
	var Wipe = 'wipe';
}

@:enum
abstract RedisDumpCommand(String) {
	var Queue = 'queue';
	var Pool = 'pool';
	var All = 'all';
}

/**
 * CLI for interacted with the platform server and tools
 */
class Cli
{
	public static function main()
	{
		var _streams :StdStreams = {out:js.Node.process.stdout, err:js.Node.process.stderr};

		var commander :Commander = cast Commander;
		commander
			.version(Json.parse(Fs.readFileSync('package.json', {encoding:'utf8'})).version);

		/* Vagrant commands */
		function helpVagrant() {
			log('\n  vagrant commands:\n');
			log('     ' + VagrantCommand.DestroyAll + ' <directory>');
			log('     ' + VagrantCommand.DestroyTestMachines);
		}
		commander
			.command('vagrant [cmd] [directory]')
			.alias('v')
			.description('vagrant commands to help dealing with multiple local worker machines')
			.action(function(cmd1 :String, cmd2, options) {
				var vagrantCommand :VagrantCommand = cast cmd1;
				if (cmd1 == null) {
					helpVagrant();
					return;
				}
				switch(vagrantCommand) {
					case DestroyAll:
						var dir = cmd2;
						if (dir == null) {
							log('Missing directory argument');
						} else {
							VagrantTools.removeAll(dir, true, _streams);
						}
					case DestroyTestMachines:
						destroyAllVagrantMachines()
						.pipe(function(_) {
							log('...finished removing vagrant machines');
							return Promise.promise(true);
						});
					default:
						log('Unrecognized command "' + cmd1 + '"');
				}
			})
			.on('', helpVagrant);

		/* Test utilities */
		commander
			.command('test-job [host] [command]')
			.description('Submits a job to a locally running compute queue stack')
			.action(function(host :String, command :String) {
				if (host == null) {
					host = 'localhost:9000';
				}
				var jobParams :BasicBatchProcessRequest = {
					dockerImage:'ubuntu:14.04',
					cmd: ['/bin/bash', '/inputs/script.sh'],
					parameters: {cpus:1, maxDuration:60*1000*10},
					inputs: [{type:InputSource.Inline, name:'script.sh', value:'echo "STDOUT here"\n>&2 echo "STDERR error"\necho "foo" >> /outputs/bar'}],
					inputsPath: 'TESTOUTPUTSFORK/inputs',
					outputsPath: 'TESTOUTPUTSFORK/outputs',
					resultsPath: 'TESTOUTPUTSFORK/results'
				};
				if (command != null) {
					jobParams.cmd = command.split(' ');
				}
				log('in test-job $host $command');

				// var host = ConnectionToolsDocker.getDockerHost();
				// host += ':8000';
				// host = 'localhost:8000';
				// trace("host:" + host);
				// trace('jobParams=${jobParams}');
				ClientCompute.postJob(host, jobParams)
					.pipe(function(result) {
						// trace("result:" + result);
						return ClientCompute.getJobResult(host, result.jobId);
					})
					.then(function(jobResult) {
						// trace("jobResult:\n" + Json.stringify(jobResult, null, '    '));
						trace(Json.stringify(jobResult, null, '    '));
					});
			});
		commander
			.command('getJob <jobId>')
			.description('Get the result of a job')
			.action(function(jobId :String) {
				var host = ConnectionToolsDocker.getDockerHost();
				host += ':8000';
				host = 'localhost:8000';
				ClientCompute.getJobResult(host, jobId)
					.then(function(jobResult) {
						trace("jobResult:\n" + Json.stringify(jobResult, null, '    '));
					});
			});

		/* Config upload */
		commander
			.command('uploadconfig <dokkucontainer> <configfile>')
			.description('Sets configuration from a config file to a remote dokku container')
			.action(function(container :String, configfile :String) {
				if (container == null) {
					log('Missing argument(s)');
					return;
				}
				var blob = InitConfigTools.getConfigFromFile(configfile);
				var envvars = InitConfigTools.configToEnvVars(blob);
				log('Setting in container $container\n' + envvars);
				// ChildProcess.e
			});

		/* Redis commands */
		function helpRedis() {
			log('\n  redis commands:\n');
			log('     ' + RedisCommand.Dump + ' <pool|queue|all>');
			log('     wipe');
			log('     cpus');
		}
		commander
			.command('redis [cmd] [arg]')
			.alias('r')
			.description('Redis commands for getting info from the db')
			.action(function(cmd1 :String, cmd2 :String, options) {
				var redisCommand :RedisCommand = cast cmd1;
				if (cmd1 == null) {
					helpRedis();
					return;
				}
				var redis = ccc.compute.ConnectionToolsRedis.getRedisClient();

				function doCommandPromise(_) {
					switch(redisCommand) {
						case Dump:
							var arg :RedisDumpCommand = cast cmd2;
							if (arg == null) {
								arg = RedisDumpCommand.All;
							}

							function dumpPool() {
								return Promise.promise(true)
									.pipe(function(_) {
										return InstancePool.toJson(redis);
									})
									.then(function(out) {
										log(Json.stringify(out, null, '  '));
										return true;
									});
							}
							function dumpQueue() {
								return Promise.promise(true)
									.pipe(function(_) {
										return ComputeQueue.toJson(redis);
									})
									.then(function(out) {
										log(Json.stringify(out, null, '  '));
										return true;
									});
							}

							return Promise.promise(true)
								.pipe(function(_) {
									return switch(arg) {
										case Queue:
											dumpQueue();
										case Pool:
											dumpPool();
										case All:
											Promise.whenAll([dumpPool(), dumpQueue()])
												.thenTrue();
										default:
											log('Argument not recognized');
											Promise.promise(true);
									}
								});

						case AvailableCpus:
							return Promise.promise(true)
								.pipe(function(_) {
									return InstancePool.toJson(redis);
								})
								.then(function(out :InstancePoolJsonDump) {
									var helper :InstancePoolJson = out;
									log('Available CPUs: ' + helper.getAllAvailableCpus());
									return true;
								});

						case Wipe:
							return js.npm.RedisUtil.deleteAllKeys(redis)
								.then(function(_) {
									log('Deleted all redis keys');
									return true;
								});
						default:
							log('Unrecognized redis command "' + cmd1 + '"');
							return Promise.promise(true);
					}
				}

				//Initialize, then do the command, then clean up
				Promise.promise(true)
					.pipe(function(_) {
						return ComputeQueue.init(redis);
					})
					.pipe(function(_) {
						return InstancePool.init(redis);
					})
					// .pipe(doCommandPromise)
					.pipe(function(_) {
						var p = doCommandPromise(false);
						if (p != null) {
							return p;
						} else {
							return Promise.promise(true);
						}
					})
					.then(function(_) {
						redis.end();
					});
			})
			.on('', helpRedis);

		commander.parse(js.Node.process.argv);

		if (Node.process.argv.slice(2).length == 0) {
			commander.help();
		}
	}

	public static function destroyAllVagrantMachines() :Promise<Bool>
	{
		var pathsToDestroyVagrantBoxes = [
			compute.TestVagrant.ROOT_PATH,
			compute.TestDockerCompute.ROOT_PATH,
			compute.TestDockerVagrant.ROOT_PATH,
			ccc.compute.workers.WorkerProviderVagrant.ROOT_PATH
		];

		return Promise.whenAll(pathsToDestroyVagrantBoxes.map(function(path) {
			return VagrantTools.removeAll(path, true, null);
		}))
		.pipe(function(_) {
			return Promise.promise(true);
		});
	}

	static function log(s :String)
	{
		js.Node.console.log(s);
	}
}