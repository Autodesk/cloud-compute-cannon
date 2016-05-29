package util;

class ArrayTools
{
	public static function array<A>(it :Iterator<A>) :Array<A>
	{
		var a = new Array<A>();
		while(it.hasNext()) {
			a.push(it.next());
		}
		return a;
	}
}