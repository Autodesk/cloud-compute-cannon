package ccc.storage;

// import js.npm.Ssh.ConnectOptions;
// import js.npm.PkgCloud.StorageClientP;

typedef StorageDefinition = {
	var type: StorageSourceType;
	@:optional var rootPath: String;
	@:optional var container :String;
	@:optional var credentials :Dynamic;
	@:optional var httpAccessUrl :String;

	// var type :StorageSourceType;
	// @:optional var rootPath :String;
	// @:optional var sshConfig :ConnectOptions;
	// @:optional var storageClient :StorageClientP;
	// @:optional var container :String;
	// @:optional var httpAccessUrl :String;
}