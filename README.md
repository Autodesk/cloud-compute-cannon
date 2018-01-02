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

Cloud Compute Cannon (CCC) aims to provide a consistent API and client libraries to run computation jobs, such as machine learning, GPU computation. It consists of a number of servers that process docker compute jobs.

It can run locally on your machine, or just as easily, in the cloud (currently only AWS but working to extend). When running in the cloud, you can scale as much or as little as you need, and you get billed directly by AWS.

It aims to be as *simple* and *reliable* to install in any location, and both local and cloud installs are a few simple steps.

A JSON-RPC REST API is provided, allowing CCC to be used by individuals, or by companies that require a reliable and scalable way of running any docker-based jobs.

Expected primary users are developers, data scientists, and researchers. For you all, there has to be an easier way to run your compute jobs. Hopefully, this tool makes your lives easier.

Cloud Compute Cannon is open source.

## Example

Install the CCC stack to the cloud, and run some computation jobs, get the results, then destroy the stack.

### 1 Install a stack locally

See `[etc/terraform/README.md](etc/terraform/README.md)`. Install the example stack in AWS (you will be charged a small amount of monay).

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
