# Developing cloud-compute-cannon

- [ARCHITECTURE](ARCHITECTURE.md)

## Set up:

Run these once:

- Install [docker](https://docs.docker.com/engine/installation/)
- OPTIONAL: Install [node.js/npm](https://nodejs.org/en/download/)
- `git clone git@github.com:dionjwa/cloud-compute-cannon.git` (or your fork)
- `cd cloud-compute-cannon`
- `./bin/install` (OR if you have node.js+npm installed: `npm run init`)

Then you can start the stack with:

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

	npm run set-build:server

This modifies the file `build.hxml` in the project root. This file is the default used by haxe IDE/editor plugins (although it can also be changed).

See other options run `npm run | grep set-build`

## Running tests

	./bin/test

These tests run in Travis CI on every pull request.

### Running scaling tests

	./bin/test-scaling

These have problems on Travis CI so are only run locally (due to timing issues, Travis CI machines are quite slow).

### Postman tests and example requests

If running locally, go to:

	http://localhost:8080

You will see links to various dashboards. There is a button for Postman API requests that you can run against the service.