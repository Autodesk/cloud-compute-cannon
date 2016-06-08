const https = require('https');

https.globalAgent.options.ca = [require('fs').readFileSync('etc/registry/certs/client-cert.pem', {encoding:'utf8'})];
console.log(https.globalAgent.options);

var options = {
  hostname: 'registry.host',
  port: 5001,
  path: '/v2/_catalog',
  method: 'GET',
  // ca: require('fs').readFileSync('etc/registry/certs/client-cert.pem')
};

// console.log(options);

var req = https.request(options, (res) => {
  console.log('statusCode: ', res.statusCode);
  // console.log('headers: ', res.headers);

  res.on('data', (d) => {
    process.stdout.write(d);
  });
});
req.end();

req.on('error', (e) => {
  console.error(e);
});