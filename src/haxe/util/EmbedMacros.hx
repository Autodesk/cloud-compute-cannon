package util;

#if macro
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.ComplexTypeTools;
import haxe.macro.TypeTools;
import haxe.macro.MacroStringTools;
import haxe.macro.Printer;
#end

class EmbedMacros
{
	macro public static function embedFiles(dir :String) :Expr
	{
		var pos = Context.currentPos();
		var files = getAllFiles(dir);
		for (f in files) {
			Context.addResource(f, sys.io.File.getBytes(f));
		}

		return macro $v{1};
	}

	static function getAllFiles(dir :String) :Array<String>
	{
		var arr = [];
		recursiveGetAllFiles(dir, arr);
		return arr;
	}

	static function recursiveGetAllFiles(dir :String, files :Array<String>)
	{
		var currentFiles = sys.FileSystem.readDirectory(dir);
		for (f in currentFiles) {
			var fullPath = haxe.io.Path.join([dir, f]);
			if (sys.FileSystem.isDirectory(fullPath)) {
				recursiveGetAllFiles(fullPath, files);
			} else {
				files.push(fullPath);
			}
		}
	}
}