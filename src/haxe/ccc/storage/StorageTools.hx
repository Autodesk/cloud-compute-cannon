package ccc.storage;

import ccc.storage.ServiceStorage;
import ccc.storage.StorageDefinition;
import ccc.compute.Definitions;

import js.npm.PkgCloud;
import js.npm.PkgCloud.StorageClientP;
import js.npm.ssh2.Ssh.ConnectOptions;

using StringTools;

class StorageTools
{
	public static function getStorage(config :StorageDefinition) :ServiceStorage
	{
		return switch(config.type) {
			case Sftp:
				new ServiceStorageSftp().setConfig(config);
			case Local:
				new ServiceStorageLocalFileSystem().setConfig(config);
			case PkgCloud:
				new ServiceStoragePkgCloud().setConfig(config);
			case S3:
				new ServiceStorageS3().setConfig(config);
			default:
				throw 'unrecognized storage type: ${config.type}';
		}
	}
}