package ccc.compute.workflows;

import haxe.DynamicAccess;
import haxe.io.*;

import haxe.remoting.JsonRpc;

import js.node.Buffer;
import js.node.Fs;
import js.npm.shortid.ShortId;

import promhx.RequestPromises;
import promhx.deferred.DeferredPromise;

import util.streams.StreamTools;

class TestWorkflows extends haxe.unit.async.PromiseTest
{
	static var TEST_BASE = 'tests/workflows';

	@inject public var _storage :ccc.storage.ServiceStorage;

	@timeout(120000)
	public function testWorkflow01() :Promise<Bool>
	{
		var url = SERVER_LOCAL_RPC_URL + '/workflow/run?wait=true&cache=0';

		var promise = new DeferredPromise();

		var formData :DynamicAccess<Dynamic> = {};
		for (file in ['input.txt', 'workflow.json']) {
			var fileName = file;
			var stream = Fs.createReadStream('test/workflows/${file}');
			formData.set(file, stream);
			stream.on('error', function(err) {
				Log.error('Failed to read stream from $fileName err=$err');
			});
		}
		//Simply by making this request a multi-part request is is assumed
		//to be a job submission.
		js.npm.request.Request.post({url:url, formData:formData},
			function(err :js.Error, httpResponse :js.npm.request.Request.HttpResponse, body:js.npm.request.Request.Body) {
				if (err != null) {
					Log.error(err);
					promise.boundPromise.reject(err);
					return;
				}
				if (httpResponse.statusCode == 200) {
					try {
						var result :WorkflowResult = Json.parse(body);
						var workflowError = result.error;
						assertIsNull(workflowError);
						var outputs :DynamicAccess<String> = result.output;
						assertNotNull(outputs['some_output']);
						var outputUrl = outputs['some_output'];
						if (!outputUrl.startsWith('http')) {
							outputUrl = 'http://${SERVER_LOCAL_HOST}/$outputUrl';
						}

						RequestPromises.get(outputUrl)
							.then(function(output) {
								assertEquals(output, 'foobarbbbb\n');
								promise.resolve(true);
							});

					} catch (err :Dynamic) {
						traceRed('Failed to parse JSON job result from body=$body err=$err');
						promise.boundPromise.reject(err);
					}
				} else {
					promise.boundPromise.reject('status code=${httpResponse.statusCode} body=$body');
				}
			});
		return promise.boundPromise;
	}

	public function new() {}
}