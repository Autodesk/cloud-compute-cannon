package util;

/**
 * Manages colors for tasks to help clean up the console
 */
class CliColors
{
	inline public static function colorFromString(s :String) :String
	{
		return COLOR_INDEX[Math.floor(Math.abs(haxe.crypto.Crc32.make(haxe.io.Bytes.ofString(s)))) % (COLOR_INDEX.length)];
	}

	public static function colorTransformFromString(s :String) :String->String
	{
		var color = colorFromString(s);
		var f :String->String = Reflect.field(js.npm.CliColor, color);
		return f;
	}

	public static function createColorTransformStream(color :String)
	{
		var f :String->String = Reflect.field(js.npm.CliColor, color);
		var transform = util.streams.StreamTools.createTransformStreamString(f);
		return transform;
	}

	static var COLOR_INDEX = [
		'red',
		'blue',
		'cyan',
		'green',
		'magenta',
		'yellow',
		'redBright',
		'greenBright',
		'yellowBright',
		'blueBright',
		'magentaBright',
		'cyanBright',
		'whiteBright',
	];
}