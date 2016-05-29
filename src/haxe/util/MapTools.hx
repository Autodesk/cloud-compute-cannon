package util;

class MapTools
{
	public static function createStringMap<V>(arr :Array<String>, f :String->V) :Map<String,V>
	{
		var map = new haxe.ds.StringMap();
		for (e in arr) {
			map.set(e, f(e));
		}
		return map;
	}

	public static function createStringMapi<V>(keys :Array<String>, values :Array<V>) :Map<String,V>
	{
		Assert.that(keys.length <= values.length);
		var map = new haxe.ds.StringMap();
		for (i in 0...keys.length) {
			map.set(keys[i], values[i]);
		}
		return map;
	}
}