/**
 * Exposes the API of the server is a more convenient way,
 * and provides some utility methods.
 */
var Promise = require("bluebird");
var request = require("request");
var WebSocket = require("ws");

var RPC_METHOD_JOB_NOTIFY = 'batchcompute.jobnotify';

exports.postJob = function(computeServerAddress, jobSubmissionParams, forms)// :Promise<{jobId:JobId}>
{
	console.log('postJob computeServerAddress=' + computeServerAddress);
	return new Promise(function(resolve, reject) {
		var formData = {
			jsonrpc: JSON.stringify(
			{
				method: '',
				params: jobSubmissionParams,
				jsonrpc: '2.0'

			})
		};
		if (forms != null) {
			for (f in forms) {
				formData[f] = forms[f];
			}
		}

		var url = 'http://' + computeServerAddress + '/rpc';
		console.log('url=' + url);
		request.post({url:url, formData: formData},
			function(err, httpResponse, body) {
				if (err != null) {
					console.error(err);
					reject(err);
					return;
				}
				if (httpResponse.statusCode == 200) {
					try {
						// var result :JobResult = Json.parse(body);
						var result = JSON.parse(body);
						resolve(result.result);
					} catch (err) {
						console.error(err);
						reject(err);
					}
				} else {
					reject('non-200 response');
				}
			});

	});
}

exports.getJobResult = function(wsAddress, jobId)// :Promise<String>//JobResult>
{
	return new Promise(function(resolve, reject) {
		if (jobId != null) {
			var ws = new WebSocket('ws://' + wsAddress);
			ws.on('message', function(data, flags) {
				ws.close();
				var jsonRpcResult = JSON.parse(data + '');
				if (jsonRpcResult.error != null) {
					reject(jsonRpcResult.error);
				} else {
					resolve(jsonRpcResult.result);
				}
			});
			ws.on('open', function () {
				ws.send(JSON.stringify({method:RPC_METHOD_JOB_NOTIFY, params:{jobId:jobId}}));//, {binary: false}
			});
		} else {
			reject('jobId is null');
		}
	});
}