/**
 * Errors don't get automatically stringified properly when converted to JSON
 * http://stackoverflow.com/questions/18391212/is-it-not-possible-to-stringify-an-error-using-json-stringify
 */

class ErrorToJson
{
	static function __init__()
	{
#if js
		untyped __js__("
			if (!('toJSON' in Error.prototype))
				Object.defineProperty(Error.prototype, 'toJSON', {
				value: function () {
					var alt = {};

					Object.getOwnPropertyNames(this).forEach(function (key) {
						alt[key] = this[key];
					}, this);

					return alt;
				},
				configurable: true,
				writable: true
			})
		");
#end
	}
}