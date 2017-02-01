package util;

class ErrorTools
{
	public static function create(message :Dynamic, ?pos:haxe.PosInfos) :js.Error
	{
		var errorJson = {message:message, fileName:pos.fileName, lineNumber:pos.lineNumber, methodName:pos.methodName, className:pos.className};
		var errorString = haxe.Json.stringify(errorJson);
		var e = new js.Error(errorString);
		Reflect.setField(e, 'toString', function() return errorString);
		Reflect.setField(e, 'toJson', function() errorJson);
		return e;
	}
}