package ccc.compute.client.cli;

import ccc.compute.client.ClientCompute;
import ccc.compute.client.ClientTools;
import ccc.compute.JobTools;
import ccc.compute.InitConfigTools;
import ccc.compute.ServiceBatchCompute;
import ccc.compute.workers.WorkerProviderTools;
import ccc.compute.server.ProviderTools;
import ccc.compute.server.ProviderTools.*;
import ccc.compute.client.cli.CliTools.*;
import ccc.storage.ServiceStorageLocalFileSystem;

import haxe.Resource;

import js.Node;
import js.node.http.*;
import js.node.ChildProcess;
import js.node.Path;
import js.node.stream.Readable;
import js.node.Fs;
import js.npm.fsextended.FsExtended;
import js.npm.request.Request;

import promhx.Promise;
import promhx.RequestPromises;
import promhx.deferred.DeferredPromise;

import yaml.Yaml;

import util.SshTools;
import util.streams.StreamTools;

using ccc.compute.ComputeTools;
using promhx.PromiseTools;
using StringTools;
using DateTools;
using Lambda;
using t9.util.ColorTraces;

enum ClientResult {
	Websocket;
}

typedef ClientJobRecord = {
	var jobId :JobId;
	var jobRequest :BasicBatchProcessRequest;
}

typedef JobWaitingStatus = {
	var jobId :JobId;
	var status :String;
	@:optional var error :Dynamic;
	@:optional var job : JobDataBlob;
}

@:enum
abstract DevTestCommand(String) to String from String {
	var longjob = 'longjob';
	var shellcommand = 'shellcommand';
}

typedef SubmissionDataBlob = {
	var jobId :JobId;
}

/**
 * "Remote" methods that run locally
 */
class ClientCommands
{
	@rpc({
		alias:'version',
		doc:'Client and server version'
	})
	public static function versionCheck() :Promise<CLIResult>
	{
		return getVersions()
			.then(function(versionBlob) {
				trace(Json.stringify(versionBlob, null, '\t'));
				if (versionBlob.server != null && versionBlob.server.npm != versionBlob.client.npm) {
					warn('Version mismatch');
					return CLIResult.ExitCode(1);
				} else {
					return CLIResult.Success;
				}
			});
	}

	static var DEV_TEST_JOBS = 'longjob | shellcommand';
	@rpc({
		alias:'devtest',
		doc:'Various convenience functions for dev testing. [longjob | shellcommand]',
		args:{
			'command':{doc: 'longjob | shellcommand'}
		}
	})
	public static function devtest(command :String, ?shell :String) :Promise<CLIResult>
	{
		var devCommand :DevTestCommand = command;
		if (devCommand == null && shell != null) {
			devCommand = DevTestCommand.shellcommand;
		}
		if (devCommand == null) {
			log('Available commands: [$DEV_TEST_JOBS]');
			return Promise.promise(CLIResult.Success);
		} else {
			return switch(command) {
				case longjob:
					var jobRequest :BasicBatchProcessRequest = {
						image: DOCKER_IMAGE_DEFAULT,
						cmd: ['sleep', '500'],
						wait: true
					}
					runInternal(jobRequest)
						.then(function(jobResult) {
							traceGreen(Json.stringify(jobResult, null, '  '));
						})
						.thenVal(CLIResult.Success);
				case shellcommand:
					var jobRequest :BasicBatchProcessRequest = {
						image: DOCKER_IMAGE_DEFAULT,
						cmd: ['/bin/sh', '-c', shell],
						wait: true
					}
					runInternal(jobRequest)
						.then(function(jobResult) {
							traceGreen(Json.stringify(jobResult, null, '  '));
						})
						.thenVal(CLIResult.Success);
				default:
					log('Unknown command=$command. Available commands: [$DEV_TEST_JOBS]');
					Promise.promise(CLIResult.PrintHelpExit1);
			}
		}
	}

	@rpc({
		alias:'run',
		doc:'Run docker job(s) on the compute provider.',
		args:{
			command: {doc:'Command to run in the docker container, specified as 1) a single word such as the script path 2) a single quoted string, which will be split (via spaces) into words (e.g. "echo foo") 3) a single string of a JSON array, e.g. \'[\"echo\",\"boo\"]\'. Space delimited commands are problematic to parse correctly.', short:'c'},
			directory: {doc: 'Path to directory containing the job definition', short:'d'},
			image: {doc: 'Docker image name [ubuntu:14.04]', short: 'm'},
			input: {doc:'Input values (decoded into JSON values) [input]. E.g.: --input foo1=SomeString --input foo2=2 --input foo3="[1,2,3,4]". ', short:'i'},
			inputfile: {doc:'Input files [inputfile]. E.g. --inputfile foo1=/home/user1/Desktop/test.jpg" --input foo2=/home/me/myserver/myfile.txt ', short:'f'},
			inputurl: {doc:'Input urls (downloaded from the server) [inputurl]. E.g. --input foo1=http://someserver/test.jpg --input foo2=http://myserver/myfile', short:'u'},
			results: {doc: 'Results directory [./<results_dir>/<date string>__<jobId>/]. The contents of that folder will have an inputs/ and outputs/ directories. ', short:'r'},
			wait: {doc: 'Wait until the job is finished before returning (default is to return the jobId immediately, then query using that jobId, since jobs may take a long time)', short:'w'},
		},
		docCustom: 'Example:\n cloudcannon run --image=elyase/staticpython --command=\'["python", "-c", "print(\\\"Hello World!\\\")"]\''
	})
	public static function runclient(
		?command :String,
		?image :String,
		?directory :String,
		?input :Array<String>,
		?inputfile :Array<String>,
		?inputurl :Array<String>,
		?results :String,
		?wait :Bool = false
		)
	{
		var commandArray :Array<String> = null;
		if (command != null) {
			if (command.startsWith('[')) {
				try {
					commandArray = Json.parse(command);
				} catch(ignoredError :Dynamic) {}
			} else {
				commandArray = command.split(' ').filter(function(s) return s.length > 0).array();
			}
		}
		var jobParams :BasicBatchProcessRequest = {
			image: image != null ? image : Constants.DOCKER_IMAGE_DEFAULT,
			cmd: commandArray,
			parameters: {cpus:1, maxDuration:60*1000*10},
			inputs: [],
			wait: wait
		};
		return runCli(jobParams, input, inputfile, inputurl, results);
	}

	@rpc({
		alias:'runjson',
		doc:'Run docker job(s) on the compute provider.',
		args:{
			jsonfile: {doc: 'Path to json file with the job spec'},
			input: {doc:'Input files/values/urls [input]. Formats: --input "foo1=@/home/user1/Desktop/test.jpg" --input "foo2=@http://myserver/myfile --input "foo3=4". ', short:'i'},
			inputfile: {doc:'Input files/values/urls [input]. Formats: --input "foo1=@/home/user1/Desktop/test.jpg" --input "foo2=@http://myserver/myfile --input "foo3=4". ', short:'i'},
			results: {doc: 'Results directory [./<results_dir>/<date string>__<jobId>/]. The contents of that folder will have an inputs/ and outputs/ directories. '},
		},
		docCustom: 'Example:\n cloudcannon run --image=elyase/staticpython --command=\'["python", "-c", "print(\\\\\\\"Hello Worlds!\\\\\\\")"]\''
	})
	public static function runJson(
		jsonfile: String,
		?input :Array<String>,
		?inputfile :Array<String>,
		?inputurl :Array<String>,
		?results: String,
		?wait: Bool = false
		)
	{
		var jobParams :BasicBatchProcessRequest = Json.parse(Fs.readFileSync(jsonfile, 'utf8'));
		if (jobParams.wait == null) {
			jobParams.wait = wait;
		}
		return runCli(jobParams, input, inputfile, inputurl, results);
	}

	static function runCli(
		jobParams: BasicBatchProcessRequest,
		?input :Array<String>,
		?inputfile :Array<String>,
		?inputurl :Array<String>,
		?results: String,
		?json :Bool = true) :Promise<CLIResult>
	{
		return runInternal(jobParams, input, inputfile, inputurl, results)
			.then(function(submissionData :JobResult) {
				//Write the client job file
				var dateString = Date.now().format("%Y-%m-%d");
				var resultsBaseDir = results != null ? results : 'results';
				var clientJobFileDirPath = Path.join(resultsBaseDir, '${dateString}__${submissionData.jobId}');
				FsExtended.ensureDirSync(clientJobFileDirPath);
				var clientJobFilePath = Path.join(clientJobFileDirPath, Constants.SUBMITTED_JOB_RECORD_FILE);
				FsExtended.writeFileSync(clientJobFilePath, Json.stringify(submissionData, null, '\t'));
				var stdout = json ? Json.stringify(submissionData, null, '\t') : submissionData.jobId;
				log(stdout);
				return CLIResult.Success;
			})
			.errorPipe(function(err) {
				trace(err);
				return Promise.promise(CLIResult.ExitCode(1));
			});
	}

	static function runInternal(
		jobParams: BasicBatchProcessRequest,
		?input :Array<String>,
		?inputfile :Array<String>,
		?inputurl :Array<String>,
		?results: String,
		?json :Bool = true) :Promise<JobResult>
	{
		// var dateString = Date.now().format("%Y-%m-%d");
		// var resultsBaseDir = results != null ? results : 'results';

		//Construct the inputs
		var inputs :Array<ComputeInputSource> = [];
		if (input != null) {
			for (inputItem in input) {
				var tokens = inputItem.split('=');
				var inputName = tokens.shift();
				inputs.push({
					type: InputSource.InputInline,
					value: tokens.join('='),
					name: inputName
				});
			}
		}
		if (inputurl != null) {
			for (url in inputurl) {
				var tokens = url.split('=');
				var inputName = tokens.shift();
				var inputUrl = tokens.join('=');
				inputs.push({
					type: InputSource.InputUrl,
					value: inputUrl,
					name: inputName
				});
			}
		}

		jobParams.inputs = jobParams.inputs == null ? inputs :jobParams.inputs.concat(inputs);

		var inputStreams = {};
		if (inputfile != null) {
			for (file in inputfile) {
				var tokens = file.split('=');
				var inputName = tokens.shift();
				var inputPath = tokens.join('=');
				var stat = Fs.statSync(inputPath);
				if (!stat.isFile()) {
					throw('ERROR no file $inputPath');
				}
				Reflect.setField(inputStreams, inputName, Fs.createReadStream(inputPath, {encoding:'binary'}));
			}
		}

		var address = getServerAddress();
		return Promise.promise(true)
			.pipe(function(_) {
				return ClientTools.postJob(address, jobParams, inputStreams);
			});
	}

	@rpc({
		alias:'image-build',
		doc:'Build a docker image from a context (directory containing a Dockerfile).',
	})
	public static function buildDockerImage(path :String, repository :String) :Promise<CLIResult>
	{
		trace('buildDockerImage path=$path repository=$repository');
		var host = getHost();
		var tarStream = js.npm.tarfs.TarFs.pack(path);
		var url = 'http://${host}$SERVER_URL_API_DOCKER_IMAGE_BUILD/$repository';
		function onError(err) {
			Log.error(err);
			trace(err);
		}
		tarStream.on(ReadableEvent.Error, onError);
		return RequestPromises.postStreams(url, tarStream)
			.pipe(function(response) {
				var responsePromise = new DeferredPromise<CLIResult>();
				response.on(ReadableEvent.Error, onError);
				response.once(ReadableEvent.End, function() {
					responsePromise.resolve(CLIResult.Success);
				});
				response.pipe(Node.process.stdout);
				return responsePromise.boundPromise;
			})
			.errorPipe(function(err) {
				trace(err);
				return Promise.promise(CLIResult.ExitCode(-1));
			});
	}

	@rpc({
		alias:'wait',
		doc:'Wait on jobs. Defaults to all currently running jobs, or list jobs with wait <jobId1> <jobId2> ... <jobIdn>',
	})
	public static function wait(job :Array<String>) :Promise<CLIResult>
	{
		var host = getHost();
		var promises = [];
		var clientProxy = getProxy(host.rpcUrl());
		return Promise.promise(true)
			.pipe(function(_) {
				if (job == null || job.length == 0) {
					return clientProxy.jobs();
				} else {
					return Promise.promise(job);
				}
			})
			.pipe(function(jobIds) {
				var promises = if (jobIds != null) {
						jobIds.map(function(jobId) {
							return function() return ClientCompute.getJobResult(host, jobId);
						});
					} else {
						[];
					}
				return PromiseTools.chainPipePromises(promises)
					.then(function(jobResults) {
						return CLIResult.Success;
					});
			});
	}

	static function waitInternal(?job :Array<JobId>) :Promise<Array<JobWaitingStatus>>
	{
		trace('waitInternal is not yet implemented');
		return Promise.promise([]);
		//Gather all job.json files in the base dir
		// var jobFiles = FsExtended.listFilesSync(js.Node.process.cwd(), {recursive:true, filter:function(itemPath :String, stat) return itemPath.endsWith(Constants.SUBMITTED_JOB_RECORD_FILE)});
		// return getServerAddress()
		// 	.pipe(function(address) {
		// 		var promises :Array<Promise<JobWaitingStatus>>= [];
		// 		for (jobFile in jobFiles) {
		// 			var submissionData :ClientJobRecord = null;
		// 			try {
		// 				submissionData = Json.parse(FsExtended.readFileSync(jobFile, {}));
		// 			} catch(err :Dynamic) {
		// 				trace(err);
		// 				continue;
		// 			}

		// 			var jobId :JobId = submissionData.jobId;
		// 			if (job != null && !job.has(jobId)) {
		// 				continue;
		// 			}
		// 			var baseResultsDir = Path.dirname(jobFile);
		// 			var resultsJsonFile = Path.join(baseResultsDir, JobTools.RESULTS_JSON_FILE);

		// 			var resultsJsonFileExists = FsExtended.existsSync(resultsJsonFile);
		// 			if (resultsJsonFileExists) {
		// 				var result :JobWaitingStatus = {jobId:jobId, status:'finished', job:null};
		// 				promises.push(Promise.promise(result));
		// 			} else {
		// 				//Check if the results have been downloaded locally
		// 				var outputsPath = submissionData.jobRequest.outputsPath;

		// 				var p = ClientCompute.getJobResult(address, jobId)
		// 					.then(function(jobResult) {
		// 						FsExtended.writeFileSync(resultsJsonFile, jsonString(jobResult));
		// 						//TODO: download output/input files
		// 						var result :JobWaitingStatus = {jobId:jobId, status:'finished just now', job:jobResult};
		// 						return result;
		// 					})
		// 					.errorPipe(function(err) {
		// 						trace('err=${err}');
		// 						var result :JobWaitingStatus = {jobId:jobId, status:'error', error:err, job:null};
		// 						return Promise.promise(result);
		// 					});
		// 				promises.push(p);
		// 			}
		// 		}
		// 		return Promise.whenAll(promises);
		// 	});
	}

	// @rpc({
	// 	alias:'info',
	// 	doc:'Info on the current setup',
	// 	args:{
	// 		'json':{doc: 'Output is JSON', short: 'j'}
	// 	}
	// })
	// public static function info(?json :Bool = true) :Promise<Bool>
	// {
	// 	var result = {
	// 		server_connection_file: null,
	// 		server_running: false
	// 	}

	// 	result.server_connection_file = CliTools.findExistingServerConfigPath();
	// 	return Promise.promise(true)
	// 		.pipe(function(_) {
	// 			if (result.server_connection_file != null) {
	// 				var path = result.server_connection_file;
	// 				result.server_connection_file += '/$LOCAL_CONFIG_DIR/$SERVER_CONNECTION_FILE';
	// 				var connectionBlob = readServerConfig(path);
	// 				var host :Host = getHostFromServerConfig(connectionBlob.data);
	// 				return ProviderTools.serverCheck(host)
	// 					.then(function(ok) {
	// 						result.server_running = ok;
	// 						return true;
	// 					});
	// 			} else {
	// 				return Promise.promise(true);
	// 			}
	// 		})
	// 		.then(function(_) {
	// 			log(Json.stringify(result, null, '\t'));
	// 			return true;
	// 		});
	// }

	@rpc({
		alias:'terminate',
		doc:'Shut down the remote server(s) and workers, and delete server files locally',
	})
	public static function serverShutdown(?confirm :Bool = false) :Promise<CLIResult>
	{
		if (!confirm) {
			traceYellow('To prevent accidentally destroying the server installation, run this command again with "--confirm" to terminate all instances.');
			return Promise.promise(CLIResult.Success);
		}

		var path :CLIServerPathRoot = Node.process.cwd();
		if (!isServerConnection(path)) {
			log('No server configuration @${path.getServerYamlConfigPath()}. Nothing to shut down.');
			return Promise.promise(CLIResult.Success);
		}
		var serverBlob :ServerConnectionBlob = readServerConnection(path);
		var localServerPath = path.getLocalServerPath();
		if (path.localServerPathExists() && serverBlob.provider == null) {
			var promise = new DeferredPromise();
			js.node.ChildProcess.exec('docker-compose stop', {cwd:localServerPath}, function(err, stdout, stderr) {
				if (err != null) {
					log(err);
				}
				if (stdout != null) {
					Node.process.stdout.write(stdout);
				}
				if (stderr != null) {
					Node.process.stderr.write(stderr);
				}
				js.node.ChildProcess.exec('docker-compose rm -f', {cwd:localServerPath}, function(err, stdout, stderr) {
					if (err != null) {
						log(err);
					}
					if (stdout != null) {
						Node.process.stdout.write(stdout);
					}
					if (stderr != null) {
						Node.process.stderr.write(stderr);
					}
					promise.resolve(CLIResult.Success);
				});
			});
			return promise.boundPromise
				.then(function(_) {
					trace('deleting connection file');
					deleteServerConnection(path);
					FsExtended.deleteDirSync(path.getServerYamlConfigPathDir());
					return CLIResult.Success;
				});
		} else {
			var host = getHost();
			var clientProxy = getProxy(host.rpcUrl());
			traceYellow('- Removing entire CCC cloud installation:');
			traceYellow('  - Destroying all workers and removing all jobs');
			return clientProxy.removeAllJobsAndWorkers()
				.pipe(function(_) {
					traceGreen('    - OK');
					var provider = WorkerProviderTools.getProvider(serverBlob.provider.providers[0]);
					traceYellow('  - Removing CCC server(s) ${serverBlob.server.id}');
					return provider.destroyInstance(serverBlob.server.id)
						.then(function(_) {
							traceGreen('    - OK');
							traceYellow('  - Removing local files');
							deleteServerConnection(path);
							traceGreen('    - OK');
							return CLIResult.Success;
						});
				});
		}
	}

	@rpc({
		alias:'server-stop',
		doc:'Stop down the server',
		docCustom: 'Stop, uninstall the server, and shut down workers and the server instance (if remote)'
	})
	public static function stopServer() :Promise<CLIResult>
	{
		var path :CLIServerPathRoot = Node.process.cwd();
		if (!isServerConnection(path)) {
			log('No server configuration @${path.getServerYamlConfigPath()}. Nothing to shut down.');
			return Promise.promise(CLIResult.Success);
		}
		var serverBlob :ServerConnectionBlob = readServerConnection(path);
		if (isServerLocalDockerInstall(serverBlob)) {
			var localPath = path.getLocalServerPath();
			try {
				var stdout :js.node.Buffer = js.node.ChildProcess.execSync("docker-compose stop", {cwd:localPath});
				return Promise.promise(CLIResult.Success);
			} catch(err :Dynamic) {
				traceRed(err);
				return Promise.promise(CLIResult.ExitCode(1));
			}
		} else {
			return ProviderTools.stopServer(serverBlob)
				.thenVal(CLIResult.Success);
		}
	}

	@rpc({
		alias:'server-config-update',
		doc:'Update the server configuration json file.',
		args:{
			'config':{doc: '<Path to server config yaml/json file>'}
		}
	})
	public static function updateServerConfig(config :String) :Promise<CLIResult>
	{
		var path :CLIServerPathRoot = Node.process.cwd();
		if (config != null && !FsExtended.existsSync(config)) {
			log('Missing configuration file: $config');
			return Promise.promise(CLIResult.PrintHelpExit1);
		}

		if (!isServerConnection(path)) {
			log('No existing installation @${path.getServerYamlConfigPath()}. Have you run "$CLI_COMMAND install"?');
			return Promise.promise(CLIResult.PrintHelpExit1);
		}

		var serverBlob :ServerConnectionBlob = readServerConnection(path);

		var serverConfig = InitConfigTools.getConfigFromFile(config);
		serverBlob.provider = serverConfig;
		writeServerConnection(serverBlob, path);

		return Promise.promise(CLIResult.Success);
	}

	@rpc({
		alias:'server-upgrade',
		doc:'Re-install the cloudcomputecannon server',
		args:{
			'config':{doc: '<Path to server config yaml file>', short:'c'},
			'uploadonly':{doc: 'DEBUG/DEVELOPER: Only upload server files to remote server.'}
		},
		docCustom: 'Examples:\n  server-install          (installs a local cloud-cannon-compute on your machine, via docker)\n  server-install [path to server config yaml file]    (installs a remote server)'
	})
	public static function serverUpgrade(?config :String, ?uploadonly :Bool = false) :Promise<CLIResult>
	{
		var path :CLIServerPathRoot = Node.process.cwd();

		if (!isServerConnection(path)) {
			log('No existing installation saved here or in any parent directory');
			return Promise.promise(CLIResult.PrintHelpExit1);
		}

		var serverBlob :ServerConnectionBlob = readServerConnection(path);

		if (config != null) {
			//Missing config file check
			if (!FsExtended.existsSync(config)) {
				log('Missing configuration file: $config');
				return Promise.promise(CLIResult.PrintHelpExit1);
			}
			var serverConfig = InitConfigTools.getConfigFromFile(config);
			serverBlob.provider = serverConfig;
			return Promise.promise(true)
				//Don't assume anything is working except ssh/docker connections.
				.pipe(function(_) {
					var force = true;
					return ProviderTools.installServer(serverBlob, force, uploadonly);
				})
				.then(function(_) {
					if (config != null) {
						//Write the possibly updated configuration
						writeServerConnection(serverBlob, path);
					}
					return true;
				})
				.thenVal(CLIResult.Success)
				.errorPipe(function(err) {
					warn(err);
					return Promise.promise(CLIResult.ExitCode(1));
				});
		} else {
			return install(null, null, null, null, true, false);
		}
	}

	@rpc({
		alias:'install',
		doc:'Install the cloudcomputecannon server locally or on a remote provider',
		args:{
			'config':{doc: '<Path to server config yaml file>', short:'c'},
			'host':{doc: 'Provide an existing server. The host should be the ip address and include the --key and --username parameters, or it should be an entry in your ~/.ssh/config.'},
			'key':{doc: 'SSH key or path to SSH key. Requires --host parameter'},
			'username':{doc: 'SSH username. Requires --host parameter'},
			'force':{doc: 'Even if a server exists, rebuild and restart', short:'f'},
			'uploadonly':{doc: 'DEBUG/DEVELOPER: Only upload server files to remote server.'}
		},
		docCustom: 'Examples:\n  server-install          (installs a local cloud-cannon-compute on your machine, via docker)\n  server-install [path to server config yaml file]    (installs a remote server)'
	})
	public static function install(?config :String, ?host :HostName, ?key :String, ?username :String, ?force :Bool = false, ?uploadonly :Bool = false) :Promise<CLIResult>
	{
		traceGreen('Beginning install');
		//Docker version check
		var incompatibleVersionError = 'Incompatible docker version. Needs 1.12.x';
		try {
			var stdout :js.node.Buffer = js.node.ChildProcess.execSync('docker --version', {stdio:['ignore','pipe','ignore']});
			var versionString = stdout.toString('utf8').split(' ')[2];
			var versionRegex = ~/(\d+)\.(\d+)\.(\*|\d+)/;
			if (versionRegex.match(versionString)) {
				var major = Std.parseInt(versionRegex.matched(1));
				var minor = Std.parseInt(versionRegex.matched(2));
				var patch = Std.parseInt(versionRegex.matched(3));
				if (major != 1 || minor < 12) {
					traceRed(incompatibleVersionError);
					return Promise.promise(CLIResult.ExitCode(1));
				}
			} else {
				//Cannot find version string
				traceRed('Cannot parse or find docker version');
				return Promise.promise(CLIResult.ExitCode(1));
			}
		} catch (ignored :Dynamic) {
			traceRed(incompatibleVersionError);
			return Promise.promise(CLIResult.ExitCode(1));
		}

		var path :CLIServerPathRoot = Node.process.cwd();

		if (config != null) {
			//Missing config file check
			if (!FsExtended.existsSync(config)) {
				traceRed('...Missing configuration file: $config');
				return Promise.promise(CLIResult.PrintHelpExit1);
			}


			// if (isServerConnection(path)) {
			// 	traceRed('  Existing installation @ ${path.getServerYamlConfigPath()}.\n  You cannot create a new installation without first removing the current installation.');
			// 	traceRed('  To remove an existing server run:\n      ccc server-remove');
			// 	return Promise.promise(CLIResult.ExitCode(1));
			// }

			return Promise.promise(true)
				.pipe(function(_) {
					if (isServerConnection(path)) {
						var configPath :CLIServerPathRoot = findExistingServerConfigPath();
						var serverBlob :ServerConnectionBlob = configPath != null ? readServerConnection(configPath) : null;
						var sshOptions = serverBlob.server.ssh;

						Node.process.stdout.write('  - Existing server config found @ $configPath, checking ${sshOptions.host} \n'.yellow());
						var retryAttempts = 1;
						var intervalMs = 2000;
						return SshTools.getSsh(sshOptions, retryAttempts, intervalMs, promhx.RetryPromise.PollType.regular, 'pollExistingServer', false)
							.then(function(ssh) {
								ssh.end();
								Node.process.stdout.write('    - Could connect to existing server ${sshOptions.host} \n'.green());
								return true;
							})
							.errorPipe(function(err) {
								traceRed(err);
								Node.process.stdout.write('    - Failed to connect to ${sshOptions.host} \n'.red());
								return Promise.promise(false);
							})
							.then(function(isRunning) {
								if (!isRunning) {
									throw 'Failed to connect to existing server config found @ $configPath, run "ccc server-remove" to remove this stale config';
								}
								return serverBlob;
							})
							//Write the new configuration
							.then(function(serverBlob) {
								var serverConfig = InitConfigTools.getConfigFromFile(config);
								serverBlob.provider = serverConfig;
								Node.process.stdout.write('    - Writing updated server configuration to ${path} \n'.green());
								writeServerConnection(serverBlob, path);
								return serverBlob;
							});
					} else {
						return Promise.promise(true)
							.pipe(function(_) {
								var serverConfig = InitConfigTools.getConfigFromFile(config);
								var serverBlob :ServerConnectionBlob = {
									host: null,
									provider: serverConfig
								};
								//If a host is supplied, try to get the credentials
								var sshConfig = null;
								if (host != null) {
									//Use the provided server
									//Search the ~/.ssh/config in case the key is defined there.
									if (key == null) {
										sshConfig = CliTools.getSSHConfigHostData(host);
										if (sshConfig == null) {
											throw 'No key supplied for host=$host and the host entry was not found in ~/.ssh/config';
										}
										traceGreen('...Using SSH host credentials found in ~/.ssh/config: host=${sshConfig.host}');
									} else {
										try {
											key = Fs.readFileSync(key, {encoding:'utf8'});
										} catch (err :Dynamic) {}
										if (username == null) {
											throw 'No username supplied for host=$host and the host entry was not found in ~/.ssh/config';
										}

										sshConfig = {
											privateKey: key,
											host: host,
											username: username
										}
										serverBlob.server = {
											id: null,
											hostPublic: new HostName(sshConfig.host),
											hostPrivate: null,
											ssh: sshConfig,
											docker: null
										}
									}

									//Write it without the ssh config data, since
									//we'll pick it up from the ~/.ssh/config every time
									serverBlob.host = new Host(new HostName(host), new Port(SERVER_DEFAULT_PORT));
									traceGreen('...Writing server connection to $path');
									writeServerConnection(serverBlob, path);

									//Use the actual ssh host for the main host field
									serverBlob.host = new Host(new HostName(sshConfig.host), new Port(SERVER_DEFAULT_PORT));

									//But add it here so the install procedure will work
									serverBlob.server = {
										id :null,
										hostPublic: new HostName(sshConfig.host),
										hostPrivate: null,
										ssh: sshConfig,
										docker: null
									}
									return Promise.promise(serverBlob);
								} else {
									//Create the server instance.
									//It doesn't validate or check the running containers, that is the next step
									var providerConfig = serverConfig.providers[0];
									return ProviderTools.createServerInstance(providerConfig)
										.then(function(instanceDef) {
											var serverBlob :ServerConnectionBlob = {
												host: new Host(new HostName(instanceDef.hostPublic), new Port(SERVER_DEFAULT_PORT)),
												server: instanceDef,
												provider: serverConfig
											};
											writeServerConnection(serverBlob, path);
											return serverBlob;
										});
								}
							});
					}
				})
				//Don't assume anything is working except ssh/docker connections.
				.pipe(function(serverBlob) {
					traceYellow('  - install server components');
					return ProviderTools.installServer(serverBlob, force, uploadonly)
						.then(function(_) {
							return serverBlob;
						});
				})
				.traceThen('  - cloud server successfully installed!'.green())
				.thenVal(CLIResult.Success)
				.errorPipe(function(err) {
					traceRed(Json.stringify(err, null, '  '));
					return Promise.promise(CLIResult.ExitCode(1));
				});
		} else {
			traceYellow('No configuration specified, installing locally');
			//Install and run via docker
			//First check if there is a local instance running
			var hostName :HostName = null;
			var host :String = null;
			return Promise.promise(true)
				.then(function(_) {
					hostName = ConnectionToolsDocker.getDockerHost();
					return hostName;
				})
				.pipe(function(hostname :HostName) {
					host = '$SERVER_DEFAULT_PROTOCOL://$hostname:$SERVER_DEFAULT_PORT';
					var url = '${host}$SERVER_PATH_CHECKS';
					return RequestPromises.get(url)
						.then(function(_) {
							return true;
						})
						.errorPipe(function(err) {
							//Ignore
							return Promise.promise(false);
						});
				})
				.pipe(function(isExistingServer) {
					if (isExistingServer && !force) {
						log('A local server already exists and is listening at $host');
						return Promise.promise(CLIResult.Success);
					} else {
						Node.process.stdout.write('...building');
						var localPath = path.getLocalServerPath();
						return ProviderTools.copyFilesForLocalServer(localPath)
							.pipe(function(_) {
								var promise = new DeferredPromise();
								var startScript = 'start.sh';
								Node.process.stdout.write('...starting');
								Fs.chmodSync(Path.join(localPath, startScript), '755');
								js.node.ChildProcess.execFile(startScript, {cwd:localPath}, function(err, stdout, stderr) {
									if (err != null) {
										Node.process.stdout.write('...failed\n');
										if (stdout != null) {
											Node.process.stdout.write(stdout);
										}
										if (stderr != null) {
											Node.process.stderr.write(stderr);
										}
									}
									if (err != null) {
										promise.resolve(CLIResult.ExitCode(-1));
									} else {
										Node.process.stdout.write('...success\n');
										var defaultServerConfig = InitConfigTools.getDefaultConfig();
										var serverBlob :ServerConnectionBlob = {
											host: new Host(new HostName(hostName), new Port(SERVER_DEFAULT_PORT)),
											server: null,
											provider: null
										};
										writeServerConnection(serverBlob, path);
										promise.resolve(CLIResult.Success);
									}
								});
								return promise.boundPromise;
							});
					}
				});
		}
	}

	@rpc({
		alias:'server-install-aws',
		doc:'Install the cloudcomputecannon server on AWS (Amazon Web Services)',
		args:{
			'key':{doc: 'AWS account key', short:'k'},
			'keyId':{doc: 'AWS account keyId', short:'i'}
		}
	})
	public static function serverInstallAws(?key :String, ?keyId :String) :Promise<CLIResult>
	{
		console.log('This feature is coming soon!');
		return Promise.promise(CLIResult.Success);
		// if (key == null) {
		// 	warn('Missing key');
		// 	return Promise.promise(CLIResult.ExitCode(1));
		// }
		// if (keyId == null) {
		// 	warn('Missing keyId');
		// 	return Promise.promise(CLIResult.ExitCode(1));
		// }
	}

	@rpc({
		alias:'server-config',
		doc:'Print out the current server configuration. Defaults to JSON output.',
		args:{
			'json':{doc: 'Output is JSON', short: 'j'}
		}
	})
	public static function serverConfig(?json :Bool = true) :Promise<CLIResult>
	{
		var configPath :CLIServerPathRoot = findExistingServerConfigPath();
		var serverBlob :ServerConnectionBlob = configPath != null ? readServerConnection(configPath) : null;

		var result = {
			config: serverBlob,
			path: configPath != null ? configPath.getServerYamlConfigPath() : null
		}
		if (json) {
			log(jsonString(result));
		} else {
			log(Yaml.render(result));
		}
		return Promise.promise(CLIResult.Success);
	}

	@rpc({
		alias:'server-check',
		doc:'Checks the server via SSH and the HTTP API'
	})
	public static function servercheck() :Promise<CLIResult>
	{
		var configPath = findExistingServerConfigPath();
		if (configPath == null) {
			log(Json.stringify({error:'Missing server configuration in this directory. Have you run "$CLI_COMMAND install" '}));
			return Promise.promise(CLIResult.PrintHelpExit1);
		}
		var connection = readServerConnection(configPath);
		if (connection == null) {
			log(Json.stringify({error:'Missing server configuration in this directory. Have you run "$CLI_COMMAND install" '}));
			return Promise.promise(CLIResult.PrintHelpExit1);
		}
		return ProviderTools.serverCheck(connection)
			.then(function(result) {
				result.connection_file_path = configPath.getServerYamlConfigPath();
				return result;
			})
			.pipe(function(result) {
				var host = connection.host;
				var clientProxy = getTestsProxy(host.rpcUrl());
				return clientProxy.runServerTests()
					.then(function(testResults) {
						Reflect.setField(result, 'tests', testResults);
						log(Json.stringify(result, null, '\t'));
						if (testResults.success) {
							return CLIResult.Success;
						} else {
							return CLIResult.ExitCode(1);
						}
					});
			});
	}

	@rpc({
		alias:'server-ping',
		doc:'Checks the server API'
	})
	public static function serverPing() :Promise<CLIResult>
	{
		var host = getHost();
		var url = 'http://$host/checks';
		return RequestPromises.get(url)
			.then(function(out) {
				var ok = out.trim() == SERVER_PATH_CHECKS_OK;
				log(ok ? 'OK' : 'FAIL');
				return ok ? CLIResult.Success : CLIResult.ExitCode(1);
			})
			.errorPipe(function(err) {
				log(Json.stringify({error:err}));
				return Promise.promise(CLIResult.ExitCode(1));
			});
	}

	@rpc({
		alias:'job-download',
		doc:'Given a jobId, downloads job results and data',
		args:{
			'job':{doc: 'JobId of the job to download'},
			'path':{doc: 'Path to put the results files. Defaults to ./<jobId>'}
		}
	})
	public static function jobDownload(job :JobId, ?path :String = null, ?includeInputs :Bool = false) :Promise<CLIResult>
	{
		if (job == null) {
			warn('Missing job argument');
			return Promise.promise(CLIResult.PrintHelpExit1);
		}
		// trace('jobDownload job=${job} path=${path} includeInputs=${includeInputs}');
		var downloadPath = path == null ? Path.join(Node.process.cwd(), job) : path;
		// trace('downloadPath=${downloadPath}');
		var outputsPath = Path.join(downloadPath, DIRECTORY_OUTPUTS);
		var inputsPath = Path.join(downloadPath, DIRECTORY_INPUTS);
		var host = getHost();
		// return Promise.promise(CLIResult.Success);
		// FsExtended.ensureDirSync(downloadPath);
		return doJobCommand(job, JobCLICommand.Result)
			.pipe(function(jobResult :JobResult) {
				if (jobResult == null) {
					warn('No job id: $job');
					return Promise.promise(CLIResult.ExitCode(1));
				}
				var localStorage = ccc.storage.ServiceStorageLocalFileSystem.getService(downloadPath);
				var promises = [];
				for (source in [STDOUT_FILE, STDERR_FILE, 'resultJson']) {
					var localPath = source == 'resultJson' ? 'result.json' : source;
					var sourceUrl :String = Reflect.field(jobResult, source);
					if (!sourceUrl.startsWith('http')) {
						sourceUrl = 'http://$host/$sourceUrl';
					}
					var fp = function() {
						log('Downloading $sourceUrl => $downloadPath/$localPath');
						return localStorage.writeFile(localPath, Request.get(sourceUrl))
							.errorPipe(function(err) {
								try {
									FsExtended.deleteFileSync(Path.join(downloadPath, localPath));
								} catch(deleteFileErr :Dynamic) {
									//Ignored
								}
								return Promise.promise(true);
							});
					}
					promises.push(fp);
				}
				var outputStorage = ccc.storage.ServiceStorageLocalFileSystem.getService(outputsPath);
				for (source in jobResult.outputs) {
					var localPath = source;
					var remotePath = Path.join(jobResult.outputsBaseUrl, source);
					if (!remotePath.startsWith('http')) {
						remotePath = 'http://$host/$remotePath';
					}
					var p = function() {
						log('Downloading $remotePath => $outputsPath/$localPath');
						return outputStorage.writeFile(localPath, Request.get(remotePath))
							.errorPipe(function(err) {
								try {
									FsExtended.deleteFileSync(Path.join(outputsPath, localPath));
								} catch(deleteFileErr :Dynamic) {
									//Ignored
								}
								return Promise.promise(true);
							});
					}
					promises.push(p);
				}
				if (includeInputs) {
					var inputStorage = ccc.storage.ServiceStorageLocalFileSystem.getService(inputsPath);
					for (source in jobResult.inputs) {
						var localPath = source;
						var remotePath = Path.join(jobResult.inputsBaseUrl, source);
						if (!remotePath.startsWith('http')) {
							remotePath = 'http://$host/$remotePath';
						}
						var p = function() {
							log('Downloading $remotePath => $inputsPath/$localPath');
							return inputStorage.writeFile(localPath, Request.get(remotePath))
								.errorPipe(function(err) {
									try {
										FsExtended.deleteFileSync(Path.join(inputsPath, localPath));
									} catch(deleteFileErr :Dynamic) {
										//Ignored
									}
									return Promise.promise(true);
								});
						}
						promises.push(p);
					}
				}

				return PromiseTools.chainPipePromises(promises)
					.thenVal(CLIResult.Success);
			});
	}

	@rpc({
		alias:'test',
		doc:'Test a simple job with a cloud-compute-cannon server'
	})
	public static function test() :Promise<CLIResult>
	{
		var rand = Std.string(Std.int(Math.random() * 1000000));
		var stdoutText = 'HelloWorld$rand';
		var outputText = 'output$rand';
		var outputFile = 'output1';
		var inputFile = 'input1';
		var command = ["python", "-c", 'data = open("/$DIRECTORY_INPUTS/$inputFile","r").read()\nprint(data)\nopen("/$DIRECTORY_OUTPUTS/$outputFile", "w").write(data)'];
		var image = 'elyase/staticpython';

		var jobParams :BasicBatchProcessRequest = {
			image: image,
			cmd: command,
			parameters: {cpus:1, maxDuration:60*1000*10},
			inputs: [],
			outputsPath: 'someTestOutputPath/outputs',
			inputsPath: 'someTestInputPath/inputs',
			wait: true
		};
		return runInternal(jobParams, ['$inputFile=input1$rand'], [], [], './tmp/results')
			.pipe(function(jobResult) {
				if (jobResult != null && jobResult.exitCode == 0) {
					var address = getServerAddress();
					return Promise.promise(true)
						.pipe(function(_) {
							return RequestPromises.get('http://' + jobResult.stdout)
								.then(function(stdout) {
									log('stdout=${stdout.trim()}');
									Assert.that(stdout.trim() == stdoutText);
									return true;
								});
						});
				} else {
					log('jobResult is null $jobResult');
					return Promise.promise(false);
				}
			})
			.then(function(success) {
				if (!success) {
					//Until waiting is implemented
					// log('Failure');
				}
				return success ? CLIResult.Success : CLIResult.ExitCode(1);
			})
			.errorPipe(function(err) {
				log(err);
				return Promise.promise(CLIResult.ExitCode(1));
			});
	}

	@rpc({
		alias:'job-run-local',
		doc:'Download job inputs and run locally. Useful for replicating problematic jobs.',
		args:{
			'path':{doc: 'Base path for the job inputs/outputs/results'}
		}
	})
	public static function runRemoteJobLocally(job :JobId, ?path :String) :Promise<CLIResult>
	{
		var host = getHost();
		var downloadPath = path == null ? Path.join(Node.process.cwd(), job) : path;
		downloadPath = Path.normalize(downloadPath);
		var inputsPath = Path.join(downloadPath, DIRECTORY_INPUTS);
		var outputsPath = Path.join(downloadPath, DIRECTORY_OUTPUTS);
		return doJobCommand(job, JobCLICommand.Definition)
			.pipe(function(jobDef :DockerJobDefinition) {
				trace('${jobDef}');
				FsExtended.deleteDirSync(outputsPath);
				FsExtended.ensureDirSync(outputsPath);
				var localStorage = ccc.storage.ServiceStorageLocalFileSystem.getService(downloadPath);
				var promises = [];
				//Write inputs
				var inputsStorage = ccc.storage.ServiceStorageLocalFileSystem.getService(inputsPath);
				for (source in jobDef.inputs) {
					var localPath = source;
					var remotePath = 'http://' + host + '/' + jobDef.inputsPath + source;
					var p = inputsStorage.writeFile(localPath, Request.get(remotePath))
						.errorPipe(function(err) {
							Node.process.stderr.write(err + '\n');
							return Promise.promise(true);
						});
					promises.push(p);
				}
				return Promise.whenAll(promises)
					.pipe(function(_) {
						var promise = new DeferredPromise();
						var dockerCommand = ['run', '--rm', '-v', inputsPath + ':/' + DIRECTORY_INPUTS, '-v', outputsPath + ':/' + DIRECTORY_OUTPUTS, jobDef.image.value];
						var dockerCommandForConsole = dockerCommand.concat(jobDef.command.map(function(s) return '"$s"'));
						dockerCommand = dockerCommand.concat(jobDef.command);
						trace('Command to replicate the job:\n\ndocker ${dockerCommandForConsole.join(' ')}\n');
						var process = ChildProcess.spawn('docker', dockerCommand);
						var stdout = '';
						var stderr = '';
						process.stdout.on(ReadableEvent.Data, function(data) {
							stdout += data + '\n';
							// console.log('stdout: ${data}');
						});
						process.stderr.on(ReadableEvent.Data, function(data) {
							stderr += data + '\n';
							// console.error('stderr: ${data}');
						});
						process.on('close', function(code) {
							console.log('EXIT CODE: ${code}');
							console.log('STDOUT:\n\n$stdout\n');
							console.log('STDERR:\n\n$stderr\n');
							promise.resolve(true);
						});
						return promise.boundPromise;
					})
					.thenVal(CLIResult.Success);
			});
	}

	static function doJobCommand<T>(job :JobId, command :JobCLICommand) :Promise<T>
	{
		var host = getHost();
		var clientProxy = getProxy(host.rpcUrl());
		return clientProxy.doJobCommand(command, [job])
			.then(function(out) {
				var result :TypedDynamicObject<JobId, T> = cast out;
				var jobResult :T = result[job];
				return jobResult;
			});
	}

	static function getServerAddress() :Host
	{
		return CliTools.getServerHost();
	}

	static function jsonString(blob :Dynamic) :String
	{
		return Json.stringify(blob, null, '\t');
	}

	static function getConfiguration() :ServiceConfiguration
	{
		return InitConfigTools.ohGodGetConfigFromSomewhere();
	}

	public static function validateServerAndClientVersions() :Promise<Bool>
	{
		return getVersions()
			.then(function(v) {
				return v.server == null || (v.server.npm == v.client.npm);
			});
	}

	public static function getVersions() :Promise<{client:ClientVersionBlob,server:ServerVersionBlob}>
	{
		var clientVersionBlob :ClientVersionBlob = {
			npm: Json.parse(Resource.getString('package.json')).version,
			compiler: Version.getHaxeCompilerVersion()
		}
		var result = {
			client:clientVersionBlob,
			server:null
		}
		var host = getHost();
		if (host != null) {
			var clientProxy = getProxy(host.rpcUrl());
			return clientProxy.serverVersion()
				.then(function(serverVersionBlob) {
					result.server = serverVersionBlob;
					return result;
				});
		} else {
			return Promise.promise(result);
		}
	}

	inline static function log(message :Dynamic)
	{
#if nodejs
		js.Node.console.log(message);
#else
		trace(message);
#end
	}

	inline static function warn(message :Dynamic)
	{
#if nodejs
		js.Node.console.log(js.npm.clicolor.CliColor.bold(js.npm.clicolor.CliColor.red(message)));
#else
		trace(message);
#end
	}

	static var console = {
		log: function(s) {
			js.Node.process.stdout.write(s + '\n');
		},
		error: function(s) {
			js.Node.process.stderr.write(s + '\n');
		},
	}
}