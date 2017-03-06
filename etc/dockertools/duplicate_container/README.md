# Duplicate an existing CCC server container (for testing local scaling)

	docker build -t dockerode .

	docker run --rm -ti -v /var/run/docker.sock:/var/run/docker.sock dockerode node script.js <containerId>
