package compute;

import haxe.Json;

import js.Node;
import js.node.Path;
import js.node.Fs;
import js.npm.FsExtended;
import js.npm.RedisClient;

import promhx.Promise;
import promhx.Deferred;
import promhx.Stream;
import promhx.deferred.DeferredPromise;
import promhx.PromiseTools;
import promhx.RequestPromises;

import util.RedisTools;

import ccc.compute.ComputeQueue;
import ccc.compute.ComputeTools;
import ccc.compute.InstancePool;
import ccc.compute.JobTools;
import ccc.compute.ServiceBatchCompute;
import ccc.compute.execution.Jobs;
import ccc.compute.workers.WorkerManager;
import ccc.compute.workers.WorkerProviderBoot2Docker;
import ccc.compute.client.ClientCompute;
import ccc.storage.StorageTools;
import ccc.storage.ServiceStorage;

import t9.abstracts.net.*;

import utils.TestTools;

using StringTools;
using Lambda;
using DateTools;
using promhx.PromiseTools;

class TestServiceBatchCompute extends TestComputeBase
{
	override public function setup() :Null<Promise<Bool>>
	{
		return super.setup()
			.pipe(function(_) {
				var out = untyped __js__('require("child_process").execSync("haxe etc/hxml/cli-build.hxml")');
				//Create a server in a forker process
				var envCopy = Reflect.copy(js.Node.process.env);
				// Reflect.setField(envCopy, ENV_LOG_LEVEL, 70);//js.npm.Bunyan.WARN);
				return TestTools.forkServerCompute(envCopy)
					.then(function(serverprocess) {
						_childProcess = serverprocess;
						return true;
					});
			});
	}

	@timeout(60000)
	public function testUrlInputs()
	{
		var INPUT_JSON_URL = 'http://httpbin.org/ip';
		return Promise.promise(true)
			.pipe(function(_) {
				return RequestPromises.get(INPUT_JSON_URL);
			})
			.pipe(function(ipjson) {
				var rand = Std.int(Math.random() * 1000000) + '';
				var inputName = 'input$rand';
				var outputName = 'output1';
				var scriptName = 'input1output1';
				//This script copies the input to an output file
				var scriptValue = '#!/usr/bin/env bash\ncp /${DIRECTORY_INPUTS}/$inputName /${DIRECTORY_OUTPUTS}/$outputName';
				var jobParams :BasicBatchProcessRequest = {
					image: DOCKER_IMAGE_DEFAULT,
					cmd: ['/bin/bash', '/${DIRECTORY_INPUTS}/$scriptName'],
					inputs: [
						{
							type: InputSource.InputUrl,
							value: INPUT_JSON_URL,
							name: inputName
						},
						{
							type: InputSource.InputInline,
							value: scriptValue,
							name: scriptName
						}
					]
				}

				return ClientCompute.postJob(HOST, jobParams)
					.thenWait(5000)
					.pipe(function(result) {
						var jobId = result.jobId;
						return ClientCompute.getJobData(HOST, jobId)
							.pipe(function(jobResult) {
								return Promise.promise(true);
							});
					});
			});
	}



	public function new() {}

	var _schedulingService :ServiceBatchCompute;

	static var HOST = Host.fromString('localhost:${SERVER_DEFAULT_PORT}');
}