package ccc.compute.server.util;

class AssertDefault
{
#if (debug || keep_asserts)
	public static function that(condition :Bool, ?message :String, ?pos :haxe.PosInfos):Void
	{
		if(!condition) {
			fail(message, pos);
		}
	}
	public static function notNull(e :Dynamic, ?message :String, ?pos :haxe.PosInfos):Void
	{
		if(e == null) {
			fail(message != null ? message : 'element==null', pos);
		}
	}
	public static function fail(message :String, ?pos :haxe.PosInfos)
	{
		var error = "Assertion failed!";
		if (message != null) {
			error += " " + message;
		}
		var stack = haxe.CallStack.toString(haxe.CallStack.callStack());
		error += '\n $stack';
		Log.error(error, pos);
		throw error;
	}
#else
	inline public static function that(_ :Dynamic, ?message :Dynamic, ?pos :haxe.PosInfos) {}
	inline public static function notNull(_ :Dynamic, ?message :Dynamic, ?pos :haxe.PosInfos) {}
	inline public static function fail(_ :Dynamic, ?pos :haxe.PosInfos) {}
#end
}