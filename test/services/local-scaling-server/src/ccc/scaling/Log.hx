package ccc.scaling;

class Log
{
	inline public static function debug (?message :Dynamic, ?extra :Array<Dynamic>, ?pos :haxe.PosInfos) :Void
	{
		if (ScalingServerConfig.LOG_LEVEL > 20) return;
		haxe.Log.trace(message + (extra != null ? " [" + extra.join(", ") + "]" : ""), pos);
	}

	inline public static function info (?message :Dynamic, ?extra :Array<Dynamic>, ?pos :haxe.PosInfos) :Void
	{
		if (ScalingServerConfig.LOG_LEVEL > 30) return;
		haxe.Log.trace(message + (extra != null ? " [" + extra.join(", ") + "]" : ""), pos);
	}

	inline public static function warn (?message :Dynamic, ?extra :Array<Dynamic>, ?pos :haxe.PosInfos) :Void
	{
		if (ScalingServerConfig.LOG_LEVEL > 40) return;
		haxe.Log.trace(message + (extra != null ? " [" + extra.join(", ") + "]" : ""), pos);
	}

	inline public static function error (?message :Dynamic, ?extra :Array<Dynamic>, ?pos :haxe.PosInfos) :Void
	{
		haxe.Log.trace('ERROR: ' + message + (extra != null ? " [" + extra.join(", ") + "]" : ""), pos);
	}

	inline public static function critical (?message :Dynamic, ?extra :Array<Dynamic>, ?pos :haxe.PosInfos) :Void
	{
		haxe.Log.trace('CRITICAL: ' + message + (extra != null ? " [" + extra.join(", ") + "]" : ""), pos);
	}
}