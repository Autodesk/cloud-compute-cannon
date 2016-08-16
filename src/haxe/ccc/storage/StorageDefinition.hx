package ccc.storage;

// import js.npm.ssh2.Ssh.ConnectOptions;
// import js.npm.PkgCloud.StorageClientP;

typedef StorageDefinition = {
	var type: StorageSourceType;
	@:optional var rootPath: String;
	@:optional var container :String;
	@:optional var credentials :Dynamic;
	@:optional var httpAccessUrl :String;
}