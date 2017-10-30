# Developing cloud-compute-cannon


## Steps to get set up:

Run these once:

	1. Install [docker](https://docs.docker.com/engine/installation/).
	2. `git clone git@github.com:dionjwa/cloud-compute-cannon.git` (or your fork)
	3. `cd cloud-compute-cannon`
	4. `INSTALL=true docker-compose up haxelibs && INSTALL=true docker-compose up node_modules && docker-compose up compile`

Then you can run the stack with:

	docker-compose up

## Edit, compile, restart

### Haxe installed locally

You can install [haxe](https://haxe.org/download/) (recommended). Then call:

	haxe etc/hxml/build-all.hxml

This compiles everthing. It's slower than compiling just the part you're working on, so you can run:

	npm run set-build:server

This will replace the file `./build.hxml` so that the default build target (`build.hxml`) is whatever part you're working on. Then:

	haxe build.hxml


### No Haxe installed locally

Edit code then run:

	docker-compose run compile

This will compile everything. This is a pretty slow way to developer, but it's there if really needed, or if you don't want to install haxe on your host machine.

### Compile only specific modules

To compile only the server:

	`npm run set-build:server`

This modifies the file `build.hxml` in the project root. This file is the default used by haxe IDE/editor plugins (although it can also be changed).

See other options run `npm run`

## Running tests

	TEST=true docker-compose run ccc.tests

These tests run in Travis CI on every pull request.

### Running scaling tests

	TEST_SCALING=true docker-compose run ccc.tests

These have problems on Travis CI so are only run locally.