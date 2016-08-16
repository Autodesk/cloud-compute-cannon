package util;

import haxe.Json;

import js.node.Fs;
import js.node.stream.Readable;
import js.npm.ssh2.Ssh;

import js.node.stream.Readable;
import js.node.stream.Writable;

import promhx.Promise;
import promhx.Stream;
import promhx.CallbackPromise;
import promhx.RetryPromise;
import promhx.deferred.DeferredPromise;
import promhx.deferred.DeferredStream;
import promhx.StreamPromises;

import util.streams.StdStreams;
import util.streams.StreamTools;

using promhx.PromiseTools;

typedef ExecResult = {
	var code:Int;
	var signal:String;
	var stdout:String;
	@:optional var stderr:String;
}

class SshTools
{
	public static function getSsh(config :ConnectOptions, ?attempts :Int = 10, ?delayBetweenRetries :Int = 10, ?pollType:PollType, ?logPrefix :String, ?supressLogs :Bool= false) :Promise<SshClient>
	{
		if (pollType == null) {
			pollType = PollType.regular;
		}
		logPrefix = (logPrefix == null ? '' : logPrefix) + ' host=${config.host}';
		// Reflect.setField(config, 'debug', js.Node.console.log);
		Assert.notNull(config);
		Assert.notNull(config.host);
		Assert.that(config.host != '');
		function attemptSsh() {
			var promise = new DeferredPromise();
			var ssh = new SshClient();

			ssh.once(SshClientEvent.Ready, function() {
				promise.resolve(ssh);
			});
			ssh.on(SshClientEvent.Error, function(err) {
				var configToLog = Reflect.copy(config);
				Reflect.deleteField(configToLog, 'privateKey');
				if (!promise.boundPromise.isResolved()) {
					promise.boundPromise.reject(err);
				} else {
					//We need to at least log this since without being able to pass the error to the rejected promise
					//there will be no record of the error.
					Log.error('Error connecting to ${configToLog}\nresolved=${promise.boundPromise.isResolved()} \nerr=$err');
				}
			});
			ssh.connect(config);
			return promise.boundPromise;
		}
		return RetryPromise.poll(attemptSsh, pollType, attempts, delayBetweenRetries, logPrefix, supressLogs);
	}

	public static function execute(config :ConnectOptions, command :String, ?attempts :Int = 10, ?delayBetweenRetries :Int = 10, ?pollType:PollType, ?logPrefix :String, ?supressLogs :Bool= false) :Promise<ExecResult>
	{
		return getSsh(config, attempts, delayBetweenRetries, pollType, logPrefix, supressLogs)
			.pipe(function(client) {
				return executeCommand(client, command)
					.then(function(result) {
						client.end();
						return result;
					});
			});
	}

	public static function executeCommand(ssh :SshClient, command :String) :Promise<ExecResult>
	{
		var deferred = new promhx.deferred.DeferredPromise();
		var canContinue = true;
		canContinue = ssh.exec(command, function(err, stream) {
			if (err != null) {
				Log.error({error:err, command:command});
				deferred.boundPromise.reject(err);
				return;
			}

			var ended = false;
			var closed = false;
			var result :ExecResult = {code:null, signal:null, stdout:null, stderr: null};
			//Add this, very useful for debugging
			Reflect.setField(result, 'command', command);

			function maybeResolve() {
				if (ended && closed) {
					if (!canContinue) {
						ssh.once(SshClientEvent.Continue, function() {
							deferred.resolve(result);
						});
					} else {
						deferred.resolve(result);
					}
				}
			}

			stream.on(ReadableEvent.End, function() {
				ended = true;
				maybeResolve();
			});
			stream.on(SshChannelEvent.Close, function(code:Int, signal:String) {
				closed = true;
				result.code = code;
				result.signal = signal;
				maybeResolve();
			});
			stream.on(ReadableEvent.Data, function(data) {
				if (result.stdout != null) {
					result.stdout += data;
				} else {
					result.stdout = Std.string(data);
				}
			});
			stream.on(ReadableEvent.Error, function(err) {
				Log.error({error:err, log:'ReadableEvent', command:command, source:'stdout'});
				deferred.boundPromise.reject(err);
				return;
			});
			stream.stderr.on(ReadableEvent.Data, function(data) {
				if (result.stderr != null) {
					result.stderr += data;
				} else {
					result.stderr = Std.string(data);
				}
			});
			stream.stderr.on(ReadableEvent.Error, function(err) {
				Log.error({error:err, log:'ReadableEvent', command:command, source:'stderr'});
				deferred.boundPromise.reject(err);
				return;
			});
		});
		if (!canContinue) {
			ssh.once(SshClientEvent.Continue, function() {
				canContinue = true;
			});
		}
		return deferred.boundPromise;
	}

	public static function executeCommands(ssh :ConnectOptions, commands :Array<String>, ?attempts :Int = 10, ?delayBetweenRetries :Int = 10) :Promise<Dynamic>
	{
		commands = commands.concat([]);//Make a local copy just in case it shouldn't be modified
		var command = commands.join(' && ');
		return execute(ssh, command, attempts, delayBetweenRetries);
	}

	public static function writeStringsToFiles(sshConnection :ConnectOptions, files :Map<String,String>) :Promise<Bool>
	{
		var promises = [];
		for (path in files.keys()) {
			promises.push(writeFileString(sshConnection, path, files[path]));
		}
		return Promise.whenAll(promises)
			.thenTrue();
	}

	public static function writeStream(sshConnection :ConnectOptions, data :IReadable, remotePath :String) :Promise<Bool>
	{
		return getSftp(sshConnection)
			.pipe(function(ssh) {
				return promhx.StreamPromises.pipe(data, ssh.sftp.createWriteStream(remotePath))
					.then(function(result) {
						ssh.ssh.end();
						return result;
					});
			});
	}

	public static function writeFile(sshConnection :ConnectOptions, sourceFile :String, remotePath :String) :Promise<Bool>
	{
		var data :IReadable = Fs.createReadStream(sourceFile, cast {encoding:'utf8'});
		return writeStream(sshConnection, data, remotePath);
	}

	public static function readFile(sshConnection :ConnectOptions, path :String) :Promise<IReadable>
	{
		return getSftp(sshConnection)
			.then(function(connections) {
				var sftp = connections.sftp;
				//The data from sftp streams are encoded strings:
				//https://github.com/mscdex/ssh2-streams/blob/master/SFTPStream.md
				//"The encoding can be 'utf8', 'ascii', or 'base64'."
				//This requires the use of the Base64Stream decoder below
				var readStream = sftp.createReadStream(path, {encoding:'base64'});
				readStream.once(ReadableEvent.Close, function() {
					//Close connection on the next update loop
					js.Node.setTimeout(function() {
						connections.ssh.end();
					}, 0);
				});

				var base64Converter = js.npm.base64stream.Base64Stream.decode();

				//Pass errors along to the downstream stream.
				readStream.on(ReadableEvent.Error, function(err) {
					Log.error('readFile path=$path \n' + err);
					base64Converter.emit(ReadableEvent.Error, err);
				});

				//Due to Haxe's variance rules, I have to type this twice
				//http://haxe.org/manual/type-system-variance.html
				//but on the bright side, there is no casting
				var base64ConverterWritable :IWritable = base64Converter;
				var base64ConverterReadable :IReadable = base64Converter;
				readStream.pipe(base64Converter);
				return base64ConverterReadable;
			});
	}

	public static function readFileString(sshConnection :ConnectOptions, path :String) :Promise<String>
	{
		return readFile(sshConnection, path)
			.pipe(function(readable) {
				return StreamPromises.streamToString(readable);
			});
	}

	public static function writeFileString(sshConnection :ConnectOptions, remotePath :String, fileContent :String) :Promise<Bool>
	{
		return writeStream(sshConnection, StreamTools.stringToStream(fileContent), remotePath);
	}

	public static function getSftp(config :ConnectOptions, ?attempts :Int = 10, ?delayBetweenRetries :Int = 10) :Promise<{ssh:SshClient, sftp:SFTPStream}>
	{
		return getSsh(config, attempts, delayBetweenRetries)
			.pipe(function(ssh) {
				var promise = new DeferredPromise();
				var canContinue = true;
				canContinue = ssh.sftp(function(err, sftp) {
					if (err != null) {
						promise.boundPromise.reject('getSftp\n' + err);
						return;
					}
					if (!canContinue) {
						ssh.on(SshClientEvent.Continue, function() {
							promise.resolve({ssh:ssh, sftp:sftp});
						});
					} else {
						promise.resolve({ssh:ssh, sftp:sftp});
					}
				});
				if (!canContinue) {
					ssh.once(SshClientEvent.Continue, function() {
						canContinue = true;
					});
				}
				return promise.boundPromise;
			});
	}

	public static function sftp(ssh :SshClient) :Promise<SFTPStream>
	{
		var deferred = new promhx.deferred.DeferredPromise();
		ssh.sftp(function(err, sftp :SFTPStream) {
			if (err != null) {
				deferred.boundPromise.reject(err);
				return;
			}
			deferred.resolve(sftp);
		});
		return deferred.boundPromise;
	}
}