package ccc.storage;

import ccc.storage.ServiceStorage;
import ccc.compute.Definitions;

import js.npm.PkgCloud;
import js.npm.PkgCloud.StorageClientP;
import js.npm.Ssh.ConnectOptions;

using StringTools;

class StorageTools
{
	public static function getStorage(config :StorageDefinition) :ServiceStorage
	{
		return switch(config.type) {
			case Sftp:
				Assert.notNull(config.sshConfig);
				Assert.notNull(config.sshConfig.host);
				Assert.that(config.sshConfig.host != '');
				new ServiceStorageSftp().setConfig(config);
			case Local:
				Assert.notNull(config.rootPath);
				new ServiceStorageLocalFileSystem().setConfig(config);
			case Cloud:
				Assert.notNull(config.storageClient);
				new ServiceStorageS3().setConfig(config);
			default:
				throw 'unrecognized storage type: ${config.type}';
		}
	}

	public static function getConfigFromServiceConfiguration(input :ServiceConfiguration) :StorageDefinition
	{
		Assert.notNull(input.server);

		var storageConfig = input.server.storage;
		Assert.notNull(storageConfig);
		Assert.notNull(storageConfig.type);
		Assert.notNull(storageConfig.rootPath);

		var accessURL :Null<String> = storageConfig.httpAccessUrl;

		var storageClient :Null<StorageClientP> = null;
		var defaultContainer :Null<String> = null;

		if (storageConfig.credentials != null) {
			Assert.notNull(storageConfig.defaultContainer);
			storageClient = PkgCloud.storage.createClient(storageConfig.credentials);
			defaultContainer = storageConfig.defaultContainer;
		}

		return {
			type: cast storageConfig.type,
			storageClient: storageClient,
			rootPath: storageConfig.rootPath,
			defaultContainer: defaultContainer,
			httpAccessUrl: storageConfig.httpAccessUrl
		};
	}
}