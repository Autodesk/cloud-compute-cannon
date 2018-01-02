# Cloud Compute Cannon [![Build Status](https://travis-ci.org/dionjwa/cloud-compute-cannon.svg?branch=master)](https://travis-ci.org/dionjwa/cloud-compute-cannon)

## TOC:
 - [INSTALL](docs/INSTALL.md)
 - [API](docs/API.md)
 - [ARCHITECTURE](docs/ARCHITECTURE.md)
 - [DEVELOPERS](docs/DEVELOPERS.md)
 - [ENVIRONMENT VARIABLES](src/haxe/ccc/compute/shared/ServerConfig.hx)
 - [LOGS](docs/LOGS.md)
 - [ROADMAP](docs/ROADMAP.md)

## Introduction

Cloud Compute Cannon (CCC) aims to provide a consistent API and client libraries to run computation jobs, such as machine learning, GPU computation. It consists of a number of servers that process `docker` compute jobs.

It can run locally on your machine, or just as easily, in the cloud (currently only AWS but working to extend), where it scales to as many compute machines as needed. It aims to be as *simple* and *reliable* to install in any location, and both local and cloud installs are a few simple steps.

A JSON-RPC REST API is provided, allowing CCC to be used by individuals, or by companies that require a reliable and scalable way of running any docker-based jobs.

Expected primary users are developers, data scientists, and researchers. For you all, there has to be an easier way to run your compute jobs. Hopefully, this tool makes your lives easier.

## Example

Install the CCC stack to the cloud, and run some computation jobs, get the results, then destroy the stack.

### 1 Install a stack locally

See [docs/INSTALL.md](docs/INSTALL.md).

### 2 Run a compute job

Get the URL to the API above (either http://localhost:9000 or it will be given by the `terraform apply` command) and run the following job via `cURL`:

```
	curl -X POST \
	  http://localhost:9000/v1 \
	  -H 'Cache-Control: no-cache' \
	  -H 'Content-Type: application/json' \
	  -H 'Postman-Token: c6f25ee8-adc8-5c08-8384-c24f641eef73' \
	  -d '{
	  "jsonrpc": "2.0",
	  "id": "_",
	  "method": "submitJobJson",
	  "params": {
	    "job": {
	      "wait": true,
	      "image": "busybox:latest",
	      "command": [
	        "ls",
	        "/inputs"
	      ],
	      "inputs": [
	        {
	          "name": "inputFile1",
	          "value": "foo"
	        },
	        {
	          "name": "inputFile2",
	          "value": "bar"
	        }
	      ],
	      "parameters": {
	        "maxDuration": 600000,
	        "cpus": 1
	      }
	    }
	  }
	}'
```

This simply prints the input files to `stdout`. Nothing special, except you can run any docker image you want to do pretty much anything.


## License

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
