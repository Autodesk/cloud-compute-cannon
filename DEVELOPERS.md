# Developing cloud-compute-cannon


## Steps to get set up:

Run these once:

	1. Install [docker](https://docs.docker.com/engine/installation/).
	2. `git clone git@github.com:dionjwa/cloud-compute-cannon.git`
	3. `cd cloud-compute-cannon`
	4. `docker-compose run haxelibs && docker-compose run node_modules && docker-compose run compile`

Then you can run the stack with:

	docker-compose up

## Edit, compile, restart

You can install [haxe](https://haxe.org/download/) (recommended) or edit code and compile with `docker-compose run compile` (slow).

Edit code, then recompile. The server will automatically restart on a successful compilation.

### Compile only specific modules

To comile only the server:

	`npm run set-build:server`

See other options run `npm run`

## Running tests

	TEST=true TEST_SCALING=true docker-compose run compile