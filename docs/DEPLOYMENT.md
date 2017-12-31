[Environment variables that configure the application](../src/haxe/ccc/compute/shared/ServerConfig.hx)

## High level

### Build

The following artifacts are created:

*Docker image:*

	build/server/cloud-compute-cannon-server.js
	src/web -> build/web

		These are combined to create the docker image

*Scaling lambdas:*

	lambda-autoscaling/index.js
	lambda-autoscaling/node_modules
	lambda-autoscaling/package.json
	-> The above are zipped up into:

	build/lambda-autoscaling-zip/ccc-bionano-scaling-0.2.21.zip


### Deployment

For deployment using terraform you need the following build artifacts:

 - Docker image url
 - Lambda scaling zip
 - Terraform deployment scripts

Then you add your provider keys, and run `terraform apply` in the deploy dir

Specify the deploy folder.

THE DEPLOY FOLDER IS NEVER DELETED, AND IS GIT_IGNORED. This means you can do whatever you want to the deploy, including (hopefully) committing it.


### Local

Running the stack locally consists of two steps: installing libraries and compiling, then running the stack

 1. `./bin/install`
 2. `docker-compose up`

The first step only needs to be done once.

From there, you can hit http://localhost:8080

### AWS (The only cloud provider currently supported, GCE coming soon)
