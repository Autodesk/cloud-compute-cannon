package util;

using StringTools;

class Predicates
{
	public static function startsWith(s :String) :String->Bool
	{
		return function(e :String) {
			return e.startsWith(s);
		}
	}

	public static function contains(s :String) :String->Bool
	{
		return function(e :String) {
			return e.indexOf(s) > -1;
		}
	}

	public static function either(a :Dynamic->Bool, b :Dynamic->Bool) :Dynamic->Bool
	{
		return function(e) {
			return a(e) || b(e);
		}
	}
}