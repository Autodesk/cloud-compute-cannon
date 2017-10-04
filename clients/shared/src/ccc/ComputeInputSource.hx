package ccc;

typedef ComputeInputSource = {
	var value :String;
	var name :String;
	@:optional var type :InputSource; //Default: InputInline
	@:optional var encoding :InputEncoding;
}
