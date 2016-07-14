package util;

using StringTools;

class StringUtil
{
	public static function isEmpty(s :String) :Bool
	{
		return s == null || s.length == 0;
	}

	public static function ensureEndsWith(s :String, char :String) :String
	{
		return s.endsWith(char) ? s : s + char;
	}
}