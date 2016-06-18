/**
 * This server provides a way to upload new server code
 * and restart the server process. This is much faster
 * than restarting docker containers.
 *
 * curl -X POST -T build/cloud-compute-cannon-server.js  http://localhost:9002/restart
 */

var child_process = require('child_process');
var http = require('http');
var fs = require('fs');
var express = require('express');
var bodyParser = require('body-parser');
var bunyan = require('bunyan');
var log = bunyan.createLogger({name: "reloader", host:""});

var PORT = 9002;

function isInsideContainer() {
	//http://stackoverflow.com/questions/23513045/how-to-check-if-a-process-is-running-inside-docker-container
	try {
		var stdout = child_process.execSync('cat /proc/1/cgroup', {stdio:['ignore','pipe','ignore']});
		var output = '' + stdout;
		return output.indexOf('/docker') > -1;
	} catch (ignored) {
		return false;
	}
}

// var SERVER_PATH = 'cloud-compute-cannon-server.js';
// if (!isInsideContainer()) {
	SERVER_PATH = 'build/cloud-compute-cannon-server.js';
// }

var app = express();

var appServerProcess = null;
function restartServer(cb) {
	function startServer() {
		log.info('starting_server');
		appServerProcess = child_process.fork('./' + SERVER_PATH, null, {cwd:process.cwd, env:process.env});
		appServerProcess.on('err', function(err) {
			log.error({error:err.stack, message:'Error on the forked server process'});
		});
		appServerProcess.on('exit', function() {
			log.info('server_exit');
			appServerProcess = null;
		});
		appServerProcess.on('message', function(m) {
			log.debug({forked_child_message:m});
			if (m == 'READY') {
				cb(null);
			}
		});
	}
	if (appServerProcess != null) {
		log.info('killing_server');
		appServerProcess.on('exit', function() {
			appServerProcess = null;
			startServer();
		});
		appServerProcess.kill();
	} else {
		startServer();
	}
}

app.get('/', function (req, res) {
	res.send('Functional testing server');
});

app.get('/reload', function (req, res) {
	restartServer(function(err) {
		res.send(err == null ? 'OK' : (err.stack == null ? err : err.stack));
	});
});

app.use(function (req, res, next) {
	var buffer = Buffer.concat([]);
	req.on('data', function(chunk) {
		buffer = Buffer.concat([buffer, chunk]);
	});
	req.on('end', function() {
		req.rawBody = buffer.toString('utf8');
		next();
	});
});

//Test this with:
//curl -X POST -T build/cloud-compute-cannon-server.js  http://localhost:9002/restart
app.post('/reload', function (req, res) {
	var serverCode = req.rawBody;
	// res.status(200).end();
	console.log(serverCode.substr(0, 30));
	if (serverCode != null) {
		fs.writeFileSync(SERVER_PATH, serverCode);
		restartServer(function(err) {
			res.send(err == null ? 'OK' : (err.stack == null ? err : err.stack));
		});
	} else {
		res.status(403).end();
	}
});

var httpServer = http.createServer(app);
httpServer.listen(PORT, function() {
	log.info('Restart server listening on port ' + PORT);
	restartServer(function(err) {
		if (err) {
			log.error({message:'Failed to start server', error:err.stack});
		} else {
			log.info('server_started');
		}
	});
});

//Watch for file changes, and automatically reload
var chokidar = require('chokidar');
var watcher = chokidar.watch(SERVER_PATH, {
  ignored: /[\/\\]\./,
  persistent: true,
  usePolling: true,
  interval: 100,
  binaryInterval: 300,
  alwaysStat: true,
  awaitWriteFinish: true
});
watcher.on('change', (path, stats) => {
	restartServer(function(err) {
    	if (err) {
    		log.error(err);
    	}
	});
});

var closed = false;
process.on('SIGINT', function() {
	log.warn("Caught interrupt signal");
	if (closed) {
		return;
	}
	watcher.close();
	closed = true;
	httpServer.close(function() {
		if (appServerProcess == null) {
			process.exit(0);
		} else {
			log.info('killing_server');
			appServerProcess.on('exit', function() {
				process.exit(0);
			});
			appServerProcess.kill();
		}
	});
});