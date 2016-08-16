#!/usr/bin/env node
/**
 * This server watches changes in the build directory and pushes new server
 * scripts to all the registered CCC stacks, and runs tests on those stacks.
 */

SERVER_PATH = 'build/cloud-compute-cannon-server.js';

var fs = require('fs');
var program = require('commander');
var Promise = require("bluebird");
var request = require('request');

var packageJson = JSON.stringify(fs.readFileSync('package.json', 'utf8'));

function collect(val, memo) {
  memo.push(val);
  return memo;
}

program
	.version(packageJson.version)
	.option('-s, --server [address]', 'Host address to push new builds (e.g. 192.168.50.1:9001)', collect, [])
	.parse(process.argv);

console.log(program.server);

function serverRunTests(host) {
	return new Promise(function(resolve, reject) {
		request(host, function (error, response, body) {
			if (!error && response.statusCode == 200) {
				console.log(body) // Show the HTML for the Google homepage.
			}
		});
	});
}

function reloadServerAndRunTests() {
	return new Promise(function(resolve, reject) {

	});
}

function reloadServersAndRunTests() {
	return new Promise(function(resolve, reject) {

	});
}


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
