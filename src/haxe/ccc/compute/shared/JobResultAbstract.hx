package ccc.compute.shared;

@:forward
abstract JobResultAbstract(JobResult) from JobResult to JobResult
{
	inline function new (val: JobResult)
		this = val;

	inline public function getOutputUrl(outputName :String, baseUrl :String) :String
	{
		return outputName.startsWith('http') ? outputName : (this.outputsBaseUrl != null && this.outputsBaseUrl.startsWith('http') ? '${this.outputsBaseUrl}${outputName}' : '${baseUrl}/${this.outputsBaseUrl}${outputName}');
	}

	inline public function getStdoutUrl(baseUrl :String) :String
	{
		// return this.stdout.startsWith('http') ? this.stdout : 'http://${SERVER_LOCAL_HOST}/${this.stdout}';
		return this.stdout.startsWith('http') ? this.stdout : '${baseUrl}/${this.stdout}';
	}

	inline public function getStderrUrl(baseUrl :String) :String
	{
		// return this.stderr.startsWith('http') ? this.stderr : 'http://${SERVER_LOCAL_HOST}/${this.stderr}';
		return this.stderr.startsWith('http') ? this.stderr : '${baseUrl}/${this.stderr}';
	}
}