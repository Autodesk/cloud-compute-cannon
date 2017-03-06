package ccc.compute.server.util;

class Break
{
#if debug
	/**
	 * Javascript breakpoints
	 * @return [description]
	 */
	macro public static function point()
	{
		return macro $e{haxe.macro.Context.parse('untyped __js__("debugger")', haxe.macro.Context.currentPos())};
	}
#else
	inline public static function point() :Void {};
#end
}