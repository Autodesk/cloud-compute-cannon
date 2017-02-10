//http://localhost:5000/amagod/metapage/tools/metaframeview/?url=http://localhost:9000/metaframe/

var connection = new Metaframe({debug:false});

var currentJobId = null;

function setState(state) {
	document.getElementById('status').innerHTML = state;
}

function showResult(jsonrpc) {
	setState('Idle');
	if (jsonrpc && jsonrpc.jsonrpc == '2.0') {
		if (jsonrpc.result && jsonrpc.result && jsonrpc.result.jobId && jsonrpc.result.jobId != currentJobId) {
			console.log('Ignoring job results because ' + jsonrpc.result.jobId + ' != ' + currentJobId, jsonrpc);
			return;
		}
		if (jsonrpc.error) {
			connection.setOutput('error', JSON.stringify(jsonrpc.error));
			connection.setOutput('stdout', '');
			connection.setOutput('stderr', '');
		} else {
			var result = jsonrpc.result;
			if (result.error) {
				connection.setOutput('error', JSON.stringify(result.error));
			}

			connection.setOutput('exitCode', result.exitCode);
			connection.setOutput('status', result.status);
			connection.setOutput('stdout', result.stdout);
			connection.setOutput('stderr', result.stderr);
			for (var i = 0; i < result.outputs.length; i++) {
				connection.setOutput(result.outputs[i], result.outputsBaseUrl + result.outputs[i]);
			}
		}
	}
}

function runCompute(job) {
	job.wait = false;
	connection.setOutput('exitCode', '');
	connection.setOutput('status', '');
	connection.setOutput('error', '');
	connection.setOutput('stdout', '');
	connection.setOutput('stderr', '');
	var jsonrpc = {
		jsonrpc: '2.0',
		method: 'submitJobJson',
		params: {job:job}
	};
	axios({
		method: 'post',
		url: '/api/rpc',
		data: jsonrpc,
		headers: {'Content-Type': 'application/json-rpc'},
	})
	.then(function (response) {
		connection.setOutput('error', null);
		var data = response.data;
		var thisJobId = null;
		if (data && data.result && data.result.jobId) {
			currentJobId = data.result.jobId;
			thisJobId = currentJobId;
		}
		// showResult(data);
		axios({
			method: 'post',
			url: '/api/rpc',
			data: {
				jsonrpc: '2.0',
				method: 'job-wait',
				params: {jobId:thisJobId}
			},
			headers: {'Content-Type': 'application/json-rpc'},
		})
		.then(function (response) {
			if (thisJobId == currentJobId) {
				showResult(response.data);
			}
		})
		.catch(function (error) {
			console.log(error);
			connection.setOutput('error', JSON.stringify(error));
		});
	})
	.catch(function (error) {
		console.log(error);
		connection.setOutput('error', JSON.stringify(error));
	});
}

function collectInputsAndRun() {
	var metaframeInputs = connection.getInputs();
	var job = {
		inputs: [],
		cmd: null
	};
	for (key in metaframeInputs) {
		if (key == 'jsonrpc') {

		} else if (key == 'command') {
			job.cmd = metaframeInputs[key];
		} else if (key == 'image') {
			job.image = metaframeInputs[key];
		} else {
			job.inputs.push({
				name: key,
				type: 'inline',
				value: metaframeInputs[key]
			});
		}
	}
	runCompute(job);
}

connection.on('inputs', function(inputs) {
	setState('Running');
	collectInputsAndRun();
});


