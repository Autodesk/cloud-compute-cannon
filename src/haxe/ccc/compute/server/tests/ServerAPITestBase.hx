package ccc.compute.server.tests;

class ServerAPITestBase extends haxe.unit.async.PromiseTest
{
	@inject('serverhost') public var _serverHost :Host;
	@inject('localRPCApi') public var _serverHostRPCAPI :UrlString;

	public function new() {}
}