
## CCC process environment variables (env vars):

[Environment variables](../src/haxe/ccc/compute/shared/ServerConfig.hx)

## Deployment

### Local

Running the stack locally consists of two steps: installing libraries and compiling, then running the stack

 1. `./bin/install`
 2. `docker-compose up`

The first step only needs to be done once.

From there, you can hit `http://localhost:8080/dashboard

### AWS (The only cloud provider currently supported, GCE coming soon)
