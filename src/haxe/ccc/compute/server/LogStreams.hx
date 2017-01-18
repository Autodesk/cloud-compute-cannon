package ccc.compute.server;

import js.node.stream.Writable;

import util.streams.StdStreams;

typedef LogStreamsDef = {
	var process :StdStreams;
	var compute :StdStreams;
}

@forward
abstract LogStreams(LogStreamsDef) from LogStreamsDef
{
	inline public function new (val :LogStreamsDef)
		this = val;

	public var process(get, never) :StdStreams;
	inline function get_process() :StdStreams
	{
		return this.process;
	}

	public var compute(get, never) :StdStreams;
	inline function get_compute() :StdStreams
	{
		return this.compute;
	}

	inline public function dispose() :promhx.Promise<Bool>
	{
		var promises = [];
		if (this.process != null) {
			promises.push(this.process.dispose());
		}
		if (this.compute != null) {
			promises.push(this.compute.dispose());
		}
		return promhx.Promise.whenAll(promises)
			.then(function(_) {
				return true;
			});
	}
}