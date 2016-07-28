# Cloud Compute Cannon

Cloud Compute Cannon is a tool aimed at scientists and more general users who want to use cheap cloud providers (such as Amazon) to perform large scale computes (number crunching). It aims to lower some of the biggest barriers and learning curves in getting data and custom code running on distributed cloud infrastructure. It can be run both as a command-line tool, or as a server for integrating into other tools via a REST API/websockets.

Use cases:

 - Simulating molecular dynamics
 - Numerical simulations, data crunching
 - Server infrastructure for scalable computation

Cloud Compute Cannon is designed to do one thing well: run docker-based compute jobs on any cloud provider (or your local machine) reliably, with a minimum or user intervention, and scale machines up and down as needed. Its feature set is purposefully limited, it is designed to be used standalone, or as a component in more complex tools, rather than be extended itself.

Features:

- Run on any cloud provider supported by [pkgcloud](https://github.com/pkgcloud/pkgcloud) or your local machine.
- Adding providers is straightforward, so that developers can potentially add their own company or university cloud infrastructure.
- One line installation.
- Simple configuration.
- Any programming language or tool can be used by jobs, as long as it runs under Linux ([docker](https://www.docker.com/) is used for running jobs).
- Worker machines will scale up and down as needed.
- The client can be run on the command line, or run as a server for providing an API to other tools.


## Installation

### Requirements

 - node + npm: http://nodejs.org/
 - If you are running jobs locally: [docker](https://www.docker.com/)

### Install

Cloud-compute-cannon installs globally.

	npm install -g cloud-compute-cannon

This installs the `ccc` executable.

## Running

### 'Hello world' example

--command=\'["python", "-c", "print(\\\"Hello World!\\\")"]

	ccc run --image=elyase/staticpython --command='["python", "-c", "print(\"Hello World!\")"]' --output=./localOutputDir

This assumes you have docker installed on the local machine, since we haven't specified any cloud provider, such as AWS. It instructs a worker to pull the python docker image, creates a container that runs the python command. The `output` option instructs cloudcannon to copy the results (here only the stdout) to the directory.

When the job is finished, you should see the text file `./localOutputDir/stdout` containing the string "Hello world!".

There are many other options that are documented below.

### Kibana/Elasticsearch Dashboard

You can see logs for the entire stack at:

http://<host>:5601

The first time you'll need to configure Kibana:

Click on settings in the top-line menu, choose indices and then make sure that the index name contains 'logstash-*', then click in the 'time-field' name and choose '@timestamp';

To confirm there are indices go to:

http://<host>:5601/_cat/indices

and you should see logstash-*** indices.

## Configuration

Deploying to a remote machine, or deploying anywhere that uses real cloud providers (e.g. AWS, GCE) requires passing in a configuration file.

Example config yaml files are found in `compute/servers/etc`.

Yaml config example:

```yaml

server:
  storage:
    type: "local"
    rootPath: "data/ServiceStorageLocalFileSystem"

providers:
  - type: "PkgCloud"
    maxWorkers: 2
    minWorkers: 0
    priority: 1
    #billingIncrement are measured in MINUTES. AWS defaults to 60 if this is not set
    billingIncrement: 58
    credentials:
      provider: "amazon"
      keyId: "AKIAIWJON3HDJ"
      key: "SLV3lNIPbGwv6oSyqXHoA5aIE7A"
      region: "us-west-1"
    server:
      Tags:
        - Key: "Name"
          Value: "CCC_Server"
      InstanceType: "m3.medium"
      ImageId: "ami-652c5505"
      KeyName: "ccc-keypair"
      Key: |
        -----BEGIN RSA PRIVATE KEY-----
        MIIEogIBAAKCAQEAyh+2Op9GIcRjlayC+TP6Btxklb9nkQlrKJaXlovJfHgQPOvpTnDceyzHy755
        JpsCbhrdio4GomeKHBObbD4eB5nIZ8VXQD1EhgedUxKKrW9csWyjlRbfOWEZyMmT025JIg8G4QYK
        -----END RSA PRIVATE KEY-----
    worker:
      Tags:
        - Key: "Name"
          Value: "CCC_Worker"
      InstanceType: "m3.medium"
      ImageId: "ami-61e99101"
      KeyName: "ccc-keypair"
      Key: |
        -----BEGIN RSA PRIVATE KEY-----
        MIIEogIBAAKCAQEAyh+2Op9GIcRjlayC+TP6Btxklb9nkQlrKJaXlovJfHgQPOvpTnDceyzHy755
        JpsCbhrdio4GomeKHBObbD4eB5nIZ8VXQD1EhgedUxKKrW9csWyjlRbfOWEZyMmT025JIg8G4QYK
        -----END RSA PRIVATE KEY-----
```

In the above configuration, only the `credentials.keyId` and `credentials.key` values need to be modified to run under your own AWS account.

## Testing

If you have a running server (let's assume here at *localhost:9000*), you can test if via `curl` by sending this JSON-RPC data (located in the file test/res/jsonrpctest.json).


```
	{
		"jsonrpc":"2.0",
		"method":"cloudcomputecannon.run",
		"params":{
			"job": {
				"image":"elyase/staticpython",
				"cmd": ["python", "-c", "print('Hello World!')"],
				"parameters": {"cpus":1, "maxDuration":6000000}
			}
		}
	}
```

	`curl -H "Content-Type: application/json-rpc" -X POST -d @test/res/jsonrpctest.json http://localhost:9000/api/rpc`

## Developers

CloudComputeCannon is written in [Haxe](http://haxe.org/). To develop, you'll need to install Haxe, ([Docker](https://www.docker.com/) +1.12, and [Node+NPM](http://nodejs.org/).

Steps for running the functional tests locally:

1) Clone the repo and install libraries, submodules, etc

	git clone https://github.com/Autodesk/cloud-compute-cannon
	cd cloud-compute-cannon
  npm run init

The `npm run init` command wraps steps that are identical to the Dockerfile, since that creates an environment for compiling and running the server.

To compile, run:

	haxe etc/hxml/build-all.hxml

To run you'll need the rest of the stack (database, registry, logging). In a new terminal window in the cloud-compute-cannon directory run the following command. It assumes you have ([Docker](https://www.docker.com/) installed:

	./bin/run-stack-noserver

Then in another terminal window, run:

	haxe test/testsIntegration.hxml

To run individual tests:

  ./bin/test <full.class.name>[.optionalMethod]


### Running tests on cloud providers

1) Set up an instance on e.g. AWS. Map the IP address to an entry in your ~/.ssh/config for passwordless operations. We'll call our alias "dev".

2) Create your serverconfig.yml

3)

  ./bin/reloading-stack-deploy <ssh alias (dev)> <path to serverconfig.yml>

4) On server compiles

  ./bin/reloading-stack-sync <ssh alias (dev)> <path to serverconfig.yml>

The server code and config will be copied over and the server restarted. Restaring means running the tests.

Optionally create an .env file in the root of the repo, this will be consumed by the reloading server.


## Contact

To contact the authors, please email: maintainers.bionano-cloudcomputecannon@autodesk.com or post an issue.

## License

Copyright 2015 Autodesk Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
