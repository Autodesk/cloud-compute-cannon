package ccc.compute.server;

enum ServerStartupState {
	Booting;
	LoadingConfig;
	CreateStorageDriver;
	StartingHttpServer;
	ConnectingToRedis;
	SavingConfigToRedis;
	BuildingServices;
	StartWebsocketServer;
	Ready;
}