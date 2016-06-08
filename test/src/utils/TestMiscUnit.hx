package utils;

import promhx.Promise;

import util.DockerTools;

using StringTools;

class TestMiscUnit extends haxe.unit.async.PromiseTest
{
	public function new() {}

	public function testDockerUrlParsing()
	{
		/**
			https://regex101.com/
localhost:5001/lmvconverter:5b2be4e42396
quay.io:80/bionano/lmvconverter
bionano/lmvconverter
quay.io/bionano/lmvconverter:latest
localhost:5000/lmvconverter:latest
quay.io:80/bionano/lmvconverter:c955c37
bionano/lmvconverter:c955c37
lmvconverter:c955c37
lmvconverter
temp_job_image:latest
		*/
		for (e in [
			'quay.io:80/bionano/lmvconverter',
			'bionano/lmvconverter',
			'quay.io/bionano/lmvconverter:latest',
			'localhost:5000/lmvconverter:latest',
			'quay.io:80/bionano/lmvconverter:c955c37',
			'bionano/lmvconverter:c955c37',
			'lmvconverter:c955c37',
			'lmvconverter',
			'localhost:5001/lmvconverter:5b2be4e42396',
			'temp_job_image:latest'
		]) {
			assertEquals(e, DockerTools.joinDockerUrl(DockerTools.parseDockerUrl(e)));
		}

		var url :DockerUrl = 'localhost:5001/lmvconverter:5b2be4e42396';
		assertEquals(url.name, 'lmvconverter');
		assertEquals(url.tag, '5b2be4e42396');
		assertEquals(url.registryhost.toString(), 'localhost:5001');

		url = 'temp_job_image:latest';
		assertEquals(url.tag, 'latest');
		assertEquals(url.name, 'temp_job_image');

		return Promise.promise(true);
	}
}