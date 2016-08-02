package util.streams;

import haxe.extern.EitherType;

import js.node.stream.Transform;
import js.node.stream.Readable;
import js.node.stream.Duplex;

class StreamTools
{
	public static function createTransformStream<T>(f :T->T) :IDuplex
	{
		var transform = untyped __js__('new require("stream").Transform({decodeStrings:false,objectMode:false})');
		untyped transform._transform = function(chunk :T, encoding :String, callback) {
			if (chunk != null) {
				try {
					chunk = f(chunk);
				} catch(err :Dynamic) {
					callback(err, null);
					return;
				}
			}
			callback(null, chunk);
		};
		return cast transform;
	}

	public static function createTransformPrepend(s :String) :IDuplex
	{
		var transform = untyped __js__('new require("stream").Transform({decodeStrings:false,objectMode:false})');
		untyped transform._transform = function(chunk :String, encoding :String, callback) {
			if (chunk != null) {
				chunk = s + chunk;
			}
			callback(null, chunk);
		};
		return cast transform;
	}

	inline public static function stringToStream(s :String) :Readable<Dynamic>
	{
		var stream :Readable<Dynamic> = untyped __js__('new require("stream").Readable({encoding:"utf8"})');
		untyped __js__('{0}.push({1})', stream, s);
		untyped __js__('{0}.push(null)', stream);
		return stream;
	}

	inline public static function bufferToStream(b :Buffer) :Readable<Dynamic>
	{
		var stream :Readable<Dynamic> = untyped __js__('new require("stream").Readable()');
		untyped __js__('{0}.push({1})', stream, b);
		untyped __js__('{0}.push(null)', stream);
		return stream;
	}
}