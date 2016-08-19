package;



class Scratch
{
	static function main()
	{
		//ccc.compute.server.tests.TestComputeMacros.
		buildTestContent();
		// var inputValue1 = 'some other string';
		inputValue = 'some other string' + Math.random();
		trace(inputValue);
	}

	public static macro function buildTestContent()
	{
		// var ShortId = {
		// 	generate: function() {
		// 		return UUID.uuid(8);
		// 	}
		// }
		trace('here');
		return macro {
			var inputValue :String = 'sdfsdf';
			trace('inside macro ' + inputValue);

			inputValue = 'sdfsdf' + Math.random();

			trace('inside macro ' + inputValue);
			// var inputValue = 'in${ShortId.generate()}';
			// var inputName = 'in${ShortId.generate()}';

			// var outputName1 = 'out${ShortId.generate()}';
			// var outputName2 = 'out${ShortId.generate()}';
			// var outputValue1 = 'out${ShortId.generate()}';

			// var input :ComputeInputSource = {
			// 	type: InputSource.InputInline,
			// 	value: inputValue,
			// 	name: inputName
			// }
		};
	}
}

// class MacroFoo
// {
// 	@rpc({
// 		alias:'devtest',
// 		doc:'Various convenience functions for dev testing',
// 		args:{
// 			'command':{doc: 'Output is JSON'}
// 		}
// 	})
// 	public static function devtest(command :String, ?foo :String = 'bar') :promhx.Promise<String>
// 	{
// 		return null;
// 	}
// }