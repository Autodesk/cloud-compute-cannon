package;



class Scratch
{
	static function main()
	{
		// util.EmbedMacros.embedFiles('etc');
		// trace('foo');
		// trace(haxe.Resource.listNames());
		// trace(haxe.Resource.getString(haxe.Resource.listNames()[0]));
		// 
		// var clientRpcDefinitions = t9.remoting.jsonrpc.Macros.getMethodDefinitions(batcher.cli.ClientCommands);
		var clientRpcDefinitions = t9.remoting.jsonrpc.Macros.getMethodDefinitions(MacroFoo);
		// trace('clientRpcDefinitions=${clientRpcDefinitions}');
		// 
		for (e in [
			'quay.io:80/bionano/lmvconverter',
			'bionano/lmvconverter',
			'quay.io/bionano/lmvconverter:latest',
			'localhost:5000/lmvconverter:latest',
			'quay.io:80/bionano/lmvconverter:c955c37',
			'bionano/lmvconverter:c955c37',
			'lmvconverter:c955c37',
			'lmvconverter'
			]) {
			trace(parseDockerUrl(e));
		}
	}

	
}

class MacroFoo
{
	@rpc({
		alias:'devtest',
		doc:'Various convenience functions for dev testing',
		args:{
			'command':{doc: 'Output is JSON'}
		}
	})
	public static function devtest(command :String, ?foo :String = 'bar') :promhx.Promise<String>
	{
		return null;
	}
}