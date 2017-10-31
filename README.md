# Cloud Compute Cannon [![Build Status](https://travis-ci.org/dionjwa/cloud-compute-cannon.svg?branch=master)](https://travis-ci.org/dionjwa/cloud-compute-cannon)

## TOC:

 - [API](docs/API.md)
 - [ARCHITECTURE](docs/ARCHITECTURE.md)
 - [DEVELOPERS](docs/DEVELOPERS.md)
 - [DEPLOYMENT](docs/DEPLOYMENT.md)
 - [ENVIRONMENT VARIABLES](src/haxe/ccc/compute/shared/ServerConfig.hx)
 - [LOGS](docs/LOGS.md)
 - [ROADMAP](docs/ROADMAP.md)

Cloud Compute Cannon (CCC) is a stack that provides an HTTP API for running arbitrary compute jobs that run in docker containers.

The stack runs locally or in AWS (other compute providers coming soon).


Cloud Compute Cannon allows you to create a server (that scales) that provides a REST API that allows callers to run *any* docker image.

This means that the Cloud-Compute-Cannon (CCC) server allow you to run anything on your server: Python scripts, R statistics analysis, deep learning algorithms, C++ simulations

Cloud Compute Cannon is a tool aimed at scientists and more general users who want to use cheap cloud providers (such as Amazon) to perform large scale computes (number crunching). It aims to lower some of the biggest barriers and learning curves in getting data and custom code running on distributed cloud infrastructure. It can be run both as a command-line tool, or as a server for integrating into other tools via a REST API/websockets.

Use cases:

 - Simulating molecular dynamics
 - Numerical simulations, data crunching
 - Server infrastructure for scalable computation

Cloud Compute Cannon is designed to do one thing well: run docker-based compute jobs on any cloud provider (or your local machine) reliably, with a minimum or user intervention, and scale machines up and down as needed. Its feature set is purposefully limited, it is designed to be used standalone, or as a component in more complex tools, rather than be extended itself.

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
