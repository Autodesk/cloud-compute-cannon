abstract TypedDynamicObject<K:String, T>(Dynamic<T>) from Dynamic<T>
{
  public inline function new() this = {};

  @:arrayAccess
  public inline function get(key:K):Null<T> return Reflect.field(this, key);

  @:arrayAccess
  public inline function set(key:K, value:T) Reflect.setField(this, key, value);

  public inline function exists(key:K):Bool return Reflect.hasField(this, key);

  public inline function remove(key:K):Bool return Reflect.deleteField(this, key);

  public inline function keys():Array<K> return cast Reflect.fields(this);
}