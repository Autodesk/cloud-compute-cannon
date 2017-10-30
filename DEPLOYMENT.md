## Deployment

This is under construction.

### Local

Running the stack locally consists of two steps: installing libraries and compiling, then running the stack

 1. `INSTALL=true docker-compose up haxelibs && INSTALL=true docker-compose up node_modules && docker-compose up compile`
 2. `docker-compose up`

The first step only needs to be done once.

From there, you can hit `http://localhost:8080/dashboard

### AWS (The only cloud provider currently supported, GCE coming soon)


### CCC process environment variables (env vars):

	- See (local source link): #src/haxe/ccc/compute/shared/ServerConfig.hx