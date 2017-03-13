package util;

import haxe.Resource;
import haxe.DynamicAccess;

import js.node.stream.Readable;
import js.npm.tarstream.TarStream;

import promhx.Promise;

using Lambda;
using StringTools;

class TarTools
{
	public static function createTarStreamFromStrings(entries :DynamicAccess<String>) :IReadable
	{
		var tarStream = TarStream.pack();
		for (name in entries.keys()) {
			tarStream.entry({name:name}, entries[name]);
		}
		tarStream.finalize();
		return tarStream;
	}

	public static function createTarStreamFromResources(prefix :String, removePrefix :Bool = true) :IReadable
	{
		var tarStream = js.npm.tarstream.TarStream.pack();
		Resource.listNames()
			.filter(Predicates.startsWith(prefix))
			.iter(function(resourceName) {
				var name = removePrefix ? resourceName.replace(prefix, '') : resourceName;
				tarStream.entry({name:name}, Resource.getString(resourceName));
			});
		tarStream.finalize();
		return tarStream;
	}
}