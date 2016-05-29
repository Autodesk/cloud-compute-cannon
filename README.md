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

This installs the `cloudcannon` executable.

## Running

### 'Hello world' example

	cloudcannon run --image=python --command="python -c print('Hello world!')" --output=./localOutputDir

This assumes you have docker installed on the local machine, since we haven't specified any cloud provider, such as AWS. It instructs a worker to pull the python docker image, creates a container that runs the python command. The `output` option instructs cloudcannon to copy the results (here only the stdout) to the directory.

When the job is finished, you should see the text file `./localOutputDir/stdout` containing the string "Hello world!".

There are many other options that are documented below.

### Kibana/Elasticsearch Dashboard

You can see logs for the entire stack at:

http://<host>:9200

The first time you'll need to configure Kibana:

Click on settings in the top-line menu, choose indices and then make sure that the index name contains 'logstash-*', then click in the 'time-field' name and choose '@timestamp';

To confirm there are indices go to:

http://<host>:9200/_cat/indices

and you should see logstash-*** indices.

## Configuration

Deploying to a remote machine, or deploying anywhere that uses real cloud providers (e.g. AWS, GCE) requires passing in environmental variables *and* also a yaml config file.

E.g.

	COMPUTE_CONFIG=`cat serverconfig.yaml` docker-compose up

The other environment variables are specified in the docker-compose.yml file.

Example config yaml files are found in `compute/servers/etc`.

The full list of environment variables used by the compute queue:

	PORT=9000
	REDIS_PORT=6379
	REDIS_HOST=redis
	COMPUTE_CONFIG=`cat serverconfig.yaml`

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
    billingIncrement: 60
    credentials:
      provider: "amazon"
      keyId: "AKIAIWJON3HDJNRFHCQQ"
      key: "exampleKey"
      region: "us-west-1"
      SecurityGroupId: "sg-a3eae4e7"
    worker:
      #You can set arbitrary tags here. This relies on the AWS permissions allowing tagging.
      #Tagging is not used internally, so these are optional.
      Tags:
        - Key: "Name"
          Value: "APlatformWorker_DionsTest"
        - Key: "PlatformId"
          Value: "DionsTest"
      InstanceType: "m4.large"
      #https://coreos.com/dist/aws/aws-stable.json
      ImageId: "ami-c2e490a2"
      #If you want to run the compute server outside the network where the workers are allocated, e.g. 
      #for testing, set this to true.
      usePublicIp: false
      SubnetId: "subnet-828f7ee7"
      #This is optional, it will use the default VPC security group.
      SecurityGroup: "platform-test-security-group"
      KeyName: "platform-test-keypair"
        Key: |
          -----BEGIN RSA PRIVATE KEY-----
          MIIEowIBAAKCAQEAhmr9lnVKTkk5p/Z/MFgPXHlTYyGt8EBqrXlmusPwBiSJsGtS9Pd+YFyFEsMy
          7SNAljfJrv/PaRWtOwHDIizHBkeEqQoZTOaNbieN152VwKJm/Lfe3wS2+BjyViV97iD8WBxcOWS+
          ...
          -----END RSA PRIVATE KEY-----
```

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

CloudComputeCannon is written in [Haxe](http://haxe.org/). To develop, you'll need to install Haxe, ([Docker](https://www.docker.com/), and [Node+NPM](http://nodejs.org/).

Steps for running the functional tests locally:

1) Ensure docker-machine has a default machine:

    ```
    docker-machine create --driver virtualbox default

    ```

2) Clone the repo and install libraries, submodules, etc

	git clone https://github.com/Autodesk/cloud-compute-cannon
	cd cloud-compute-cannon
  npm run init

The `npm run init` command wraps steps that are identical to the Dockerfile, since that creates an environment for compiling and running the server.

To compile, run:

	haxe etc/hxml/build-all.hxml

You'll need (at minimum) a running [Redis ](http://redis.io/) database. In a new terminal window in the cloud-compute-cannon directory run the following command. It assumes you have ([Docker](https://www.docker.com/) installed:

	npm run redis

Then in another terminal window, run:

	haxe test/testsIntegration.hxml

Some of the tests require [VirtualBox](https://www.virtualbox.org/wiki/Downloads), however these are optional (the availability of Virtualbox is detected at runtime).

### Contact

To contact the authors, please email: maintainers.bionano-cloudcomputecannon@autodesk.com or post an issue.

### License

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
