package ccc.compute.test.tests;

class ServerAPITestBase extends haxe.unit.async.PromiseTest
{
	public var _serverHost :Host = ServerTesterConfig.CCC;
	public var _serverHostUrl :UrlString = 'http://${ServerTesterConfig.CCC}';
	public var _serverHostRPCAPI :UrlString = 'http://${ServerTesterConfig.CCC}/${Type.enumConstructor(CCCVersion.v1)}';

	@inject public var injector :Injector;

	public function new()
	{
		_serverHost = ServerTesterConfig.CCC;
		_serverHostUrl = 'http://${ServerTesterConfig.CCC}';
		_serverHostRPCAPI = 'http://${ServerTesterConfig.CCC}/${Type.enumConstructor(CCCVersion.v1)}';
	}
}