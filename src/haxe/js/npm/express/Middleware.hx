package js.npm.express;

import haxe.extern.Rest;
import js.support.Callback;

abstract AbstractMiddleware( Dynamic ) 
from MiddlewareErrorHandler to MiddlewareErrorHandler 
from MiddlewareResponder to MiddlewareResponder 
from MiddlewareHandler to MiddlewareHandler
from Middleware to Middleware {}

typedef MiddlewareNext = ?Dynamic->Void;
typedef MiddlewareHandler = Request->Response->MiddlewareNext->Void;
typedef MiddlewareResponder = Request->Response->Void;
typedef MiddlewareErrorHandler = Dynamic -> Request -> Response -> Callback0 -> Void;
typedef MiddlewareParam<P> = Request -> Response -> MiddlewareNext -> P -> Void;
typedef MiddlewareMethod = Route->Middleware->Void;

extern interface Middleware {}

@:build( util.CopyMethods.build([
	'post', 
	'put', 
	'head', 
	'delete', 
	'options', 
	'trace', 
	'copy', 
	'lock', 
	'mkcol', 
	'move', 
	'purge', 
	'propfind', 
	'proppatch', 
	'unlock', 
	'report', 
	'mkactivity', 
	'checkout', 
	'merge', 
	'm-search',
	'notify', 
	'subscribe', 
	'unsubscribe', 
	'patch', 
	'search', 
	'connect',
	'all'
], 
function(path : Route , f : haxe.extern.Rest<AbstractMiddleware> ) : Application {} , [] ) )
extern class MiddlewareHttp 
{
	@:overload( function ( path : Route , middleware : Rest<AbstractMiddleware> ) : Application {} )
	public function use ( middleware : Rest<AbstractMiddleware> ) : Application ;

	function param<P>( name : String , callback : MiddlewareParam<P> ) : Application;
}
