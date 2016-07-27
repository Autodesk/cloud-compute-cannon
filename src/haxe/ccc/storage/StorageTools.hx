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
				// Assert.notNull(config.rootPath);
				new ServiceStorageLocalFileSystem().setConfig(config);
			case Cloud:
				// Assert.notNull(config.storageClient);
				new ServiceStorageS3().setConfig(config);
			default:
				throw 'unrecognized storage type: ${config.type}';
		}
	}

	// public static function getConfigFromServiceConfiguration(input :ServiceConfiguration) :StorageDefinition
	// {
	// 	Assert.notNull(input);
	// 	Assert.notNull(input.server);
	// 	Assert.notNull(input.server.storage);
	// 	return input.server.storage;
	// }
	

	// 	var storageConfig = input.server.storage;
	// 	Assert.notNull(storageConfig);
	// 	Assert.notNull(storageConfig.type);
	// 	Assert.notNull(storageConfig.rootPath);

	// 	var accessURL :Null<String> = storageConfig.httpAccessUrl;

	// 	var storageClient :Null<StorageClientP> = null;
	// 	var container :Null<String> = null;

	// 	if (storageConfig.credentials != null) {
	// 		Assert.notNull(storageConfig.container);
	// 		trace('createClient');
	// 		trace('storageConfig.credentials=${storageConfig.credentials}');
	// 		storageClient = PkgCloud.storage.createClient(storageConfig.credentials);
	// 		container = storageConfig.container;
	// 	}

	// 	return {
	// 		type: cast storageConfig.type,
	// 		storageClient: storageClient,
	// 		rootPath: storageConfig.rootPath,
	// 		container: container,
	// 		httpAccessUrl: storageConfig.httpAccessUrl
	// 	};
	// }
}