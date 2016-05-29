package promhx;

import promhx.Deferred;
import promhx.Promise;

#if nodejs
import js.Error;
#else
typedef Error=Dynamic;
#end

class CallbackPromise<T> extends Promise<T>
{
	public var cb0 (get, null) :Void->Void;
	public var cb1 (get, null) :Null<Error>->Void;
	public var cb2 (get, null) :Null<Error>->T->Void;

	public function new()
	{
		_deferred = new Deferred();
		super(_deferred);
	}

	function get_cb0() :Void->Void
	{
		return function() {
			_deferred.resolve(null);
		};
	}

	function get_cb1() :Error->Void
	{
		return function(err) {
			if (err != null) {
				reject(err);
			} else {
				_deferred.resolve(null);
			}
		};
	}

	function get_cb2() :Error->T->Void
	{
		return function(err, val) {
			if (err != null) {
				reject(err);
			} else {
				_deferred.resolve(val);
			}
		};
	}

	var _deferred :Deferred<T>;
}