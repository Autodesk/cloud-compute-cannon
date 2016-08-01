package ccc.storage;

@:enum
abstract StorageSourceType(String) {
	var Sftp = 'sftp';
	var Local = 'local';
	var PkgCloud = 'pkgcloud';
	var S3 = 'S3';
}