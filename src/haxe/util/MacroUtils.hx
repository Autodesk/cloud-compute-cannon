package util;

import haxe.macro.Expr;
import haxe.macro.Context;

class MacroUtils
{
	macro static public function compilationTime():Expr
	{
		var now_str = Date.now().toString();
		// an "ExprDef" is just a piece of a syntax tree. Something the compiler
		// creates itself while parsing an a .hx file
		return {expr: EConst(CString(now_str)) , pos : Context.currentPos()};
	}
}