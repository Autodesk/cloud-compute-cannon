# Developing cloud-compute-cannon

- [ARCHITECTURE](ARCHITECTURE.md)
- [API](API.md)
- [DEPLOYMENT](DEPLOYMENT.md)

## Set up:

Run these once:

- Install [docker](https://docs.docker.com/engine/installation/)
- OPTIONAL: Install [node.js/npm](https://nodejs.org/en/download/)
- `git clone git@github.com:dionjwa/cloud-compute-cannon.git` (or your fork)
- `cd cloud-compute-cannon`
- `./bin/install` (OR if you have node.js+npm installed: `npm run init`)

Then you can start the stack with:

	docker-compose up

If you want the functional tests to be run on code compilation, run the stack with tests enabled:

	TEST=true docker-compose up

Then, if all code is compiled, the test running server will restart the tests.

## Tests

All tests except scaling tests:

	./bin/test

Scaling only tests:

	./bin/test-scaling

Scaling tests are different because of the length of time taken, and because they remove the current CCC server/worker instance running in docker-compose (and replace it) so logs are no longer visible (a pain when developing).

Scaling tests are NOT run in travis due to unresolved timing issues, likely due to the lack of CPU. Scaling tests need to be run locally on the developers machine. However, it is not often that scaling code is modified, so integrating the two types of tests is not yet a high priority.

## Edit, compile, restart

### Haxe installed locally

You can install [haxe](https://haxe.org/download/) (recommended). Then call:

	haxe etc/hxml/build-all.hxml

This compiles everthing. It's slower than compiling just the part you're working on, so you can run:

	npm run set-build:server

This will replace the file `./build.hxml` so that the default build target (`build.hxml`) is whatever part you're working on. Then:

	haxe build.hxml

A list of haxe plugins for various editors can be found [here](https://haxe.org/documentation/introduction/editors-and-ides.html).


### No Haxe installed locally

Edit code then run:

	docker-compose run compile

This will compile everything. This is a pretty slow way to developer, but it's there if really needed, or if you don't want to install haxe on your host machine.

If you already have the stack running, then you can run (in a separate terminal window):

	docker-compose restart compile

## Compile only specific modules

To compile only the server:

	npm run set-build:server

This modifies the file `build.hxml` in the project root. This file is the default used by haxe IDE/editor plugins (although it can also be changed).

See other options run `npm run | grep set-build`

## Running tests

	./bin/test

These tests run in Travis CI on every pull request.

There are also tests for scaling and worker management. These have problems on Travis CI so are only run locally (due to timing issues, Travis CI machines are quite slow):

	./bin/test-scaling

## Postman tests and example requests

If running locally, go to:

	http://localhost:8080

You will see links to various dashboards. There is a button for Postman API requests that you can run against the service.