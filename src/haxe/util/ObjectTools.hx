package util;

import haxe.Json;
import haxe.DynamicAccess;

class ObjectTools
{
	/**
	 * obj1 fields will be overridden by obj2 fields.
	 */
	public static function mergeDeepCopy<T>(obj1 :Dynamic, obj2 :Dynamic) :T
	{
		obj1 = Json.parse(Json.stringify(obj1));
		if (obj2 == null) {
			return obj1;
		}
		obj2 = Json.parse(Json.stringify(obj2));
		merge(cast obj1, cast obj2);
		return obj1;
	}

	public static function merge(obj1 :DynamicAccess<Dynamic>, obj2 :DynamicAccess<Dynamic>)
	{
		var fields = obj2.keys();
		for (fieldName in fields) {
			var field = obj2[fieldName];
			if (!obj1.exists(fieldName)) {
				obj1[fieldName] = field;
			} else {
				var originalField = obj1[fieldName];
				switch(Type.typeof(originalField)) {
					case TObject: merge(originalField, field);
					case TClass(c): merge(originalField, field);
					default: obj1[fieldName] = field;
				}
			}
		}
	}
}