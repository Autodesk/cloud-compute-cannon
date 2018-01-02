# Installation

## Local computer

### Users

Download the following file (in this example using curl), then run using `docker-compose`:

	curl https://raw.githubusercontent.com/dionjwa/cloud-compute-cannon/master/etc/docker-compose/single-server/docker-compose.yml --output docker-compose.yml
	docker-compose up

Then go to `http://localhost:9000` to see the dashboard.

To delete the local stack:

	docker-compose stop
	docker-compose rm -fv

### Developers

See [./DEVELOPERS.md](./DEVELOPERS.md).

## Cloud (AWS)

See `[etc/terraform/README.md](etc/terraform/README.md)` for an example of installing to AWS and removing the stack when finished.
