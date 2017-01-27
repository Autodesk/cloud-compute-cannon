const CCCC = require('../../build/client/js/lib.js');

// const cccUrl = 'ccc.bionano.autodesk.com:9000';
const cccUrl = 'localhost:9000';
const ccc = CCCC.connect(cccUrl);

ccc.status()
	.then(statusResult => {
		console.log({statusResult});

		var cccInput = {};
		cccInput["Dockerfile"] = require('fs').createReadStream('Dockerfile');

		const jobJson = {
			wait: true,
			appendStdOut: true,
			appendStdErr: true,
			image: 'docker.io/busybox:latest',
			createOptions: {
				Cmd: ["/bin/sh", "-c", "cp /inputs/* /outputs/"]
			}
		};

		return ccc.run(jobJson, cccInput)
			.then(jobResult => {
				console.log({message:'finished', jobResult});
				return jobResult;
			});
	})
	.catch(err => {
		console.error("Failed", err);
	});
	

// var request = require('request');
// request.post({url:'http://localhost:34545'}, (err, status, body) => {
// 	if (err) {
// 		console.error(err);
// 		return;
// 	}
// 	console.log({status});
// });