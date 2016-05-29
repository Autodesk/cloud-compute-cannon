package js.npm.express;

import js.node.http.IncomingMessage;

typedef RequestRoute = Dynamic;
typedef RequestAccepted = Dynamic;

typedef Request = TRequest<Dynamic>;

@:native("Request")
extern class TRequest<P>
extends IncomingMessage {

	public var params : P;
	public var query : Dynamic;
	public var route : RequestRoute;
	public var accepted : Array<RequestAccepted>;
	public var ip : String;
	public var ips : Array<String>;
	public var path : String;
	public var host : String;
	public var fresh : Bool;
	public var stale : Bool;
	public var xhr : Bool;
	public var protocol : String;
	public var secure : Bool;
	public var subdomains : Array<String>;
	public var originalUrl : String;
	public var acceptedLanguages : Array<String>;
	public var acceptedCharsets : Array<String>;

	public function param( name : String ) : Null<Dynamic>;
	public function get( name : String ) : Null<String>;

	@:overload(function( mimes : Array<String> ) : Null<String> {} )
	public function accepts( mime : String ) : Null<String>;

	public function is( type : String ) : Bool;

	public function acceptsCharset( charset : String ) : Bool;
	public function acceptsLanguage( lang : String ) : Bool;


}
