package ccc.compute.test.tests;

import js.node.Fs;

import util.DockerTools;
import util.DockerUrl;

class TestUnit extends haxe.unit.async.PromiseTest
{
	public function new() {}

	public function testJobTools()
	{
		var jobId :JobId = "SkAW0gNw";
		var jobdef :DockerBatchComputeJob = {
			outputsPath : null,
			inputs : [],
			resultsPath : null,
			workingDir : null,
			command : ["echo","out52325909"],
			inputsPath : null,
			id : jobId,
			image : {
				value : DOCKER_IMAGE_DEFAULT,
				type : DockerImageSourceType.Image
			}
		};

		assertEquals(JobTools.inputDir(jobdef), '$jobId/$DIRECTORY_INPUTS/');
		assertEquals(JobTools.outputDir(jobdef), '$jobId/$DIRECTORY_OUTPUTS/');
		assertEquals(JobTools.resultDir(jobdef), '$jobId/');

		var inputsPath = 'foo';
		jobdef.inputsPath = inputsPath;

		assertEquals(JobTools.inputDir(jobdef), '$inputsPath/');

		var customInputsPath = 'customInputs';
		jobdef.inputsPath = customInputsPath;

		assertEquals(JobTools.inputDir(jobdef), '$customInputsPath/');

		return Promise.promise(true);
	}

	public function testDockerUrlParsing()
	{
		// https://regex101.com/
		for (e in [
			'quay.io:80/something/else',
			'something/lmvconverter',
			'quay.io/something/lmvconverter:latest',
			'localhost:5000/lmvconverter:latest',
			'quay.io:80/something/lmvconverter:c955c37',
			'something/lmvconverter:c955c37',
			'lmvconverter:c955c37',
			'lmvconverter',
			'localhost:5001/lmvconverter:5b2be4e42396',
			'quay.io/something/computeworker_nanodesign:1b41fba',
			'autodesk/moldesign:moldesign_complete-0.7.1'
		]) {
			assertEquals(e, DockerUrlTools.joinDockerUrl(DockerUrlTools.parseDockerUrl(e)));
		}

		var url :DockerUrl = 'localhost:5001/lmvconverter:5b2be4e42396';
		assertEquals(url.name, 'lmvconverter');
		assertEquals(url.tag, '5b2be4e42396');
		assertEquals(url.registryhost.toString(), 'localhost:5001');

		var other :DockerUrl = 'localhost:5002/lmvconverter';
		assertTrue(DockerUrlTools.matches(url, other));

		var another :DockerUrl = 'localhost:5002/lmvconverterX';
		assertFalse(DockerUrlTools.matches(url, another));

		var another2 :DockerUrl = 'lmvconverter:5b2be4e42396XXXXXX';
		assertFalse(DockerUrlTools.matches(url, another2));

		var another3 :DockerUrl = 'quay.io/something/computeworker_nanodesign:1b41fba';
		assertEquals(another3.repository, 'something/computeworker_nanodesign');
		assertEquals(another3.name, 'computeworker_nanodesign');
		assertEquals(another3.tag, '1b41fba');
		assertEquals(another3.registryhost, 'quay.io');

		var another4 :DockerUrl = 'autodesk/moldesign:moldesign_complete-0.7.1';
		assertEquals(another4.tag, 'moldesign_complete-0.7.1');

		return Promise.promise(true);
	}

	public function testTimeUnits()
	{
		var nowFloat = Date.now().getTime();
		var now = new Milliseconds(nowFloat);
		var ts = new TimeStamp(now);
		assertEquals(ts.toString(), Date.fromTime(now.toFloat()).toString());
		assertEquals(ts.toFloat(), nowFloat);

		var ms1 = new Milliseconds(20);
		var ms2 = new Milliseconds(5);
		var ms3 = ms1 - ms2;
		assertEquals(ms3.toFloat(), 15.0);

		var seconds = new Seconds(10);
		var ms = seconds.toMilliseconds().toFloat();
		var timePlus :TimeStamp = ts.addSeconds(seconds);
		var floatTimePlus = nowFloat + ms;
		var timePlusFloat :Float = timePlus.toFloat();
		assertEquals(timePlusFloat, floatTimePlus);

		var val :Float = 300.0;
		var mins = new Minutes(val);
		assertEquals(mins, val);

		return Promise.promise(true);
	}

// 	public function testSSHConfigParsing()
// 	{
// 		var fakeKeyPath = '/tmp/keyFake';
// 		var fakeKeyData = 'someFakeKey';
// 		Fs.writeFileSync(fakeKeyPath, fakeKeyData);
// 		var sshConfigData = '
// Host platform
//     User ubuntu
//     HostName ec2-54-215-14-115.us-west-1.compute.amazonaws.com
//     IdentityFile ~/.ssh/platform.pem

// Host platformdokku
//      User dokku
//      IdentityFile ~/.ssh/id_rsa_dokku_push
//      HostName ec2-54-215-14-115.us-west-1.compute.amazonaws.com
//      RequestTTY yes

// Host default
//     HostName 192.168.50.1
//     User core
//     Port 22
//     UserKnownHostsFile /dev/null
//     StrictHostKeyChecking no
//     PasswordAuthentication no
//     IdentityFile /Users/dionamago/.vagrant.d/insecure_private_key
//     IdentitiesOnly yes
//     LogLevel FATAL

// Host awsworker
//      User core
//      IdentityFile $fakeKeyPath
//      HostName ec2-54-177-176-228.us-west-1.compute.amazonaws.com
//      RequestTTY yes
// 		';

// 		var hostData = ccc.compute.server.client.cli.CliTools.getSSHConfigHostData(new HostName('awsworker'), sshConfigData);
// 		assertNotNull(hostData);
// 		assertEquals(hostData.username, 'core');
// 		assertEquals(hostData.privateKey, fakeKeyData);
// 		assertEquals(hostData.host, new HostName('ec2-54-177-176-228.us-west-1.compute.amazonaws.com'));
// 		return Promise.promise(true);
// 	}
}