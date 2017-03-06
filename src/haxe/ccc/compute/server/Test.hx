package ccc.compute.server;

class Test
{
	static function main()
	{
		var injector = new Injector();
		injector.map(String, 'VAL').toValue('FOOBAR');
		injector.injectInto(SomeStaticClass);
		// trace(SomeStaticClass.test());
	}
}

class SomeStaticClass
{
	@inject('VAL')
	public static var VAL :String;

	public static function test()
	{
		trace('VAL=$VAL');
	}
}
