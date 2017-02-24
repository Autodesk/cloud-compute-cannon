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
	macro public static function embedFiles(dir :String, exclude:Array<String>) :Expr//exclude:Array<ExprOf<String>>
	{
		var pos = Context.currentPos();
		var files = getAllFiles(dir);

		if (exclude == null) {
			exclude = [];
		}
		exclude.push('.*node_modules.*');
		exclude.push('.*\\.vagrant');
		exclude.push('.*\\.haxelib');

		var regexes = exclude.map(function(s) return new EReg(s, ''));

		var pathFilter = function(filePath :String) :Bool {
			if (regexes.length == 0) {
				return true;
			} else {
				var valid = true;
				for (reg in regexes) {
					if (reg.match(filePath)) {
						valid = false;
						break;
					}
				}
				return valid;
			}
		}
		files = files.filter(pathFilter);
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