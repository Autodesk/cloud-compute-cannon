package js.npm.express;
import js.npm.express.Middleware;
import js.support.Callback;

@:jsRequire('express', 'Router')
extern class Router 
extends MiddlewareHttp
implements Middleware
implements Dynamic<MiddlewareMethod>
{
	public function new() : Void;
	
	@:overload(function(path : Route , f : haxe.extern.Rest<AbstractMiddleware> ) : Router {})
	@:overload(function ( setting : String ): Dynamic { } )
	function get( path : Route, f : AbstractMiddleware ) : Router;

}
