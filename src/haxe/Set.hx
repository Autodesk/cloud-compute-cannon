import haxe.Constraints.IMap;

abstract Set<T>(IMap<T, Bool>)
{
	inline public static function createString<T:String>(?it :Iterable<T>) :Set<T>
	{
		var map = new Map<String, Bool>();
		if (it != null) {
			for (e in it) {
				map.set(e, true);
			}
		}
		return cast map;
	}

	inline public static function createInt<T:Int>(?it :Iterable<Int>) :Set<T>
	{
		var map = new Map<Int, Bool>();
		if (it != null) {
			for (e in it) {
				map.set(e, true);
			}
		}
		return cast map;
	}

	inline public static function createEnum<T>() :Set<T>
	{
		var map = new Map<EnumValue, Bool>();
		return cast map;
	}

	inline public static function createObject<T>(?it :Iterable<{}>) :Set<T>
	{
		var map = new Map<{}, Bool>();
		if (it != null) {
			for (e in it) {
				map.set(e, true);
			}
		}
		return cast map;
	}

	inline public function new(m:IMap<T, Bool>)
	{
		this = m;
	}

	inline public function add(e :T)
	{
		this.set(e, true);
	}

	inline public function remove(e :T)
	{
		this.remove(e);
	}

	inline public function has(e :T) :Bool
	{
		return this.exists(e);
	}

	@:arrayAccess
	inline public function get(e:T) :Bool
	{
		return this.exists(e);
	}

	inline public function iterator() :Iterator<T>
	{
		return this.keys();
	}

	inline public function length() :Int
	{
		var i = 0;
		for (x in this) {
			i++;
		}
		return i;
	}

	inline public function toString() :String
	{
		return this.toString();
	}

	inline public function array() :Array<T>
	{
		var arr = [];
		for (v in this.keys()) {
			arr.push(v);
		}
		return arr;
	}

	@:from
	inline static public function fromMap<T>(m:IMap<T, Bool>)
	{
		return cast m;
	}
}
