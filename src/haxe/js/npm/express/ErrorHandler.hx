package js.npm.express;

extern class ErrorHandler
implements npm.Package.Require<"errorhandler", "^1.3.2"> #if !haxe3,#end
implements Middleware
{
	@:overload(function(?options : Bool) : Void {})
	public function new(?options: {
		log: Dynamic -> ?String -> ?Request -> ?Response -> Void
	}) : Void;
}
