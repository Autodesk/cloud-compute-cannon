package utils;

import promhx.Promise;

import util.DockerTools;

import t9.abstracts.time.*;

using StringTools;

class TestMiscUnit extends haxe.unit.async.PromiseTest
{
	public function new() {}

	public function testDockerUrlParsing()
	{
		// https://regex101.com/
		// localhost:5001/lmvconverter:5b2be4e42396
		// quay.io:80/bionano/lmvconverter
		// bionano/lmvconverter
		// quay.io/bionano/lmvconverter:latest
		// localhost:5001/lmvconverter:latest
		// quay.io:80/bionano/lmvconverter:c955c37
		// bionano/lmvconverter:c955c37
		// lmvconverter:c955c37
		// lmvconverter
		for (e in [
			'quay.io:80/bionano/lmvconverter',
			'bionano/lmvconverter',
			'quay.io/bionano/lmvconverter:latest',
			'localhost:5000/lmvconverter:latest',
			'quay.io:80/bionano/lmvconverter:c955c37',
			'bionano/lmvconverter:c955c37',
			'lmvconverter:c955c37',
			'lmvconverter',
			'localhost:5001/lmvconverter:5b2be4e42396'
		]) {
			assertEquals(e, DockerTools.joinDockerUrl(DockerTools.parseDockerUrl(e)));
		}

		var url :DockerUrl = 'localhost:5001/lmvconverter:5b2be4e42396';
		assertEquals(url.name, 'lmvconverter');
		assertEquals(url.tag, '5b2be4e42396');
		assertEquals(url.registryhost.toString(), 'localhost:5001');

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
}