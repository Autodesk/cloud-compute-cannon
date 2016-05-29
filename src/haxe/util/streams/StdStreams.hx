package util.streams;

import js.node.stream.Writable;

typedef StdStreamsDef = {
	var out :IWritable;
	var err :IWritable;
}

@forward(out,err)
abstract StdStreams(StdStreamsDef) from StdStreamsDef
{
	inline public function new (val :StdStreamsDef)
		this = val;

	public var out(get, never) :IWritable;
	inline function get_out() :IWritable
	{
		return this.out;
	}

	public var err(get, never) :IWritable;
	inline function get_err() :IWritable
	{
		return this.err;
	}

	inline public function dispose() :promhx.Promise<Bool>
	{
		var promise = new promhx.deferred.DeferredPromise();
		var outEnded = false;
		var errEnded = false;
		function maybeResolve() {
			if (outEnded && errEnded) {
				promise.resolve(true);
			}
		}
		if (this.out != null) {
			this.out.once(WritableEvent.Finish, function() {
				outEnded = true;
				maybeResolve();
			});
			untyped this.out.unpipe();
			this.out.end();
		}
		if (this.err != null) {
			this.err.once(WritableEvent.Finish, function() {
				errEnded = true;
				maybeResolve();
			});
			untyped this.err.unpipe();
			this.err.end();
		}
		return promise.boundPromise;
	}
}
