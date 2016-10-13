package;

class Scratch
{
	static function main()
	{
		var docker = new js.npm.docker.Docker({socketPath:'/var/run/docker.socksdfsdfsdf'});
		var outputVolumeName = 'sdfsdfsfsf';
		promhx.DockerPromises.removeVolume(docker.getVolume(outputVolumeName))
			.then(function(_) {
				trace('Removed volume=$outputVolumeName');
				return true;
			})
			.errorPipe(function(err) {
				trace('Problem deleting volume ${outputVolumeName} err=${err}');
				return Promise.promise(false);
			})
			.then(function(_) {
				trace('got to end');
			});
	}
}
