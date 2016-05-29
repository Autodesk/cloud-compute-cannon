package ccc.compute.workers;

/**
 * Runtime checks on the worker provider.
 */

import haxe.Json;

import js.npm.RedisClient;

import ccc.compute.Definitions;
import ccc.compute.InstancePool;
import ccc.compute.ServiceConfiguration;
import ccc.compute.workers.WorkerProvider;

import promhx.Promise;
import promhx.Promise;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.CallbackPromise;
import promhx.RequestPromises;

import t9.abstracts.net.*;
import t9.abstracts.time.*;

class WorkerProviderChecks
{
	public static function checkWorkerCreation(provider :WorkerProvider) :Promise<Bool>
	{
		log = Logger.log.child({process:'checkWorkerCreation'})
		return Promise.promise(true)
			.pipe(function(_) {
				return provider.createIndependentWorker()
					.pipe(function(workerDef) {
						log.debug({worker:workerDef});
						//Ping fluent
						var host :IP = workerDef.ssh.host;
						var rand = Std.string(Std.int(Math.random() * 1000000));
						log.trace({log:'rand=${rand}'});
						return RequestPromises.post('http://${IP}:${FLUENTD_HTTP_COLLECTOR_PORT}/healthcheck', 'json={"file":"$rand", "nonce":"$rand"}')
							.pipe(function(response) {
								log.debug({worker:workerDef});
								log.trace({log:'response=${response}'});
								var flushWorkerLoggingBufferUrl = 'http://${IP}:$FLUENTD_API_PORT/${FLUENTD_API_PATH}';
								return RequestPromises.get(flushWorkerLoggingBufferUrl);
							})
							.pipe(function(_) {
								//Now check the content of the file
								return util.SshTools.readFileString(workerDef.ssh, '/tmp/$rand')
									then(function(s) {
										log.trace({log:'s=${s}'});
										return s.trim() == rand;
									});
							});
					});
			})
			.errorPipe(function(err) {
				log.error({error:err});
				return Promise.promise(false);
			})
			.then(function(success) {
				if (success) {
					log.info(ok:success);
				} else {
					log.warn(ok:success);
				}
				return success;
			});
	}
}