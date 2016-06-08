package util.streams;

import haxe.extern.EitherType;

import js.node.stream.Transform;
import js.node.stream.Readable;
import js.node.stream.Duplex;
import js.node.Buffer;

class StreamTools
{
	public static function createTransformStream(f :EitherType<Buffer,String>->String->(js.Error->EitherType<Buffer,String>->Void)->Void, ?options:DuplexNewOptions) :IDuplex
	{
		var transform :Transform<Dynamic> = untyped __js__('new require("stream").Transform({0})', options);
		untyped transform._transform = f;
		return transform;
	}

	public static function createTransformStreamString(f :String->String) :IDuplex
	{
		var f = function(chunk :String, encoding :String, callback) {
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
		var opts :DuplexNewOptions = {decodeStrings:false,objectMode:false};
		var transform = createTransformStream(f, opts);
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
		untyped __js__('stream.push(s)');
		untyped __js__('stream.push(null)');
		return stream;
	}
}