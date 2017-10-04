package ccc;

//https://nodejs.org/api/buffer.html
@:enum
abstract InputEncoding(String) to String from String {
	//Default
	var utf8 = 'utf8';
	var base64 = 'base64';
	var ascii = 'ascii';
	var utf16le = 'utf16le';
	var ucs2 = 'ucs2';
	var binary = 'binary';
	var hex = 'hex';
}
