var REDIS_HOST = process.env['REDIS_HOST'] || 'redis';
var REDIS_PORT = process.env['REDIS_PORT'] || 6379;

REDIS_HOST = REDIS_HOST.replace(':', '');

var app = require('bull-ui/app')({redis:{host:REDIS_HOST,port:REDIS_PORT}});
var PORT = parseInt(process.env["PORT"]) || 9001;
app.listen(PORT, function() {
	console.log('bull-ui started listening on port', this.address().port);
});