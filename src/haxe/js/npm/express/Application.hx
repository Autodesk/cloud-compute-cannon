package js.npm.express;

import js.support.Callback;

import js.npm.express.Middleware;

extern class Application 
extends MiddlewareHttp
// implements js.node.Http.IHttpServerListener
{
	public var locals : Dynamic;
	public var router : Router;

	@:overload(function( port :Int, ready : Void -> Void ): Application { } )
	public function listen (port :Int, ?address :String) : Application;

	public static function createServer (a1 :Dynamic, ?a2 :Dynamic, ?a3 :Dynamic, ?a4 :Dynamic, ?a5 :Dynamic, ?a6 :Dynamic, ?a7 :Dynamic, ?a8 :Dynamic, ?a9 :Dynamic) : Application;

	function engine( ext : String , engine : ViewEngine ) : Application;
	function set( setting : String , value : Dynamic ) : Application;

	@:overload( function ( path : Route, f : haxe.extern.Rest<AbstractMiddleware> ) : Application {} )
	@:overload( function ( f : haxe.extern.Rest<AbstractMiddleware> ) : Application {} )
	function get( setting : String ): Dynamic;
}
