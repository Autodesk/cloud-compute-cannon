package ccc.storage;

@:enum
abstract StorageSourceType(String) {
	var Sftp = 'sftp';
	var Local = 'local';
	var Cloud = 'cloud';
	//More coming
}