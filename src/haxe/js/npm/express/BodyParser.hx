package js.npm.express;

import js.node.Buffer;

typedef UrlencodedOptions = {
	extended : Bool,
	?inflate : Bool,
	?limit : Int,
	?parameterLimit : Int,
	?type : String,
	?verify : Request -> Response -> Buffer -> String -> Void
}

@:jsRequire('body-parser')
extern class BodyParser
implements Middleware
{
	public static function json(?options : {}) : BodyParser;
	public static function raw(?options : {}) : BodyParser;
	public static function text(?options : {}) : BodyParser;
	public static function urlencoded(?options : UrlencodedOptions) : BodyParser;

	public inline static function body(req : Request) : Dynamic {
		return untyped req.body;
	}
}
