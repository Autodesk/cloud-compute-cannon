package js.npm;

@:jsRequire("express")
extern class Express 

extends js.npm.express.Application #if !haxe3,#end 
{
	public function new() : Void;
	
}
