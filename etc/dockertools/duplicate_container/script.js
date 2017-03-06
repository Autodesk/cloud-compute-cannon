var Docker = require('dockerode');
var docker = new Docker({socketPath:'/var/run/docker.sock'});

var targetContainer = process.argv[process.argv.length - 1];

var container = docker.getContainer(targetContainer);

container.inspect((err, data) => {
	if (err) {
		return console.error(err);
	} else {
		console.log(data);

		var create_options = data.Config;
		create_options["AttachStdin"] = false;
		create_options["AttachStdout"] = false;
		create_options["AttachStderr"] = false;
		create_options.HostConfig = data.HostConfig;
		create_options.HostConfig.Links = ['redis', 'fluentd'];
		var start_options = {};
		docker.createContainer(create_options, function (err, container) {
			if (err) {
				console.error(err);
				process.exit(1);
			}
			container.start(function (err, data) {
				if (err) {
					console.error(err);
					process.exit(1);
				}
				console.log('Successful start!');
				console.log(data);
			});
		});
	}
});