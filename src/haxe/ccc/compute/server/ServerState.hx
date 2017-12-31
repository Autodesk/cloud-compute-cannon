package ccc.compute.server;

import ccc.compute.server.execution.routes.ServerCommands;

import haxe.remoting.JsonRpc;
import haxe.DynamicAccess;

import js.node.Process;
import js.node.http.*;
import js.npm.docker.Docker;
import js.npm.express.Express;
import js.npm.express.Application;
import js.npm.express.Request;
import js.npm.express.Response;
import js.npm.JsonRpcExpressTools;
// import js.npm.Ws;
import js.npm.redis.RedisClient;

import minject.Injector;

import ccc.storage.*;

import util.RedisTools;
import util.DockerTools;

@:forward
abstract ServerState(Injector) from Injector to Injector
{
	inline public function new(i :Injector)
	{
		this = i;
	}

	inline public function getStatus() :ServerStartupState
	{
		var state = this.getValue(ServerStartupState);
		return state;
	}

	inline public function setStatus(status :ServerStartupState)
	{
		if (this.hasMapping(ServerStartupState)) {
			this.unmap(ServerStartupState);
		}
		this.map(ServerStartupState).toValue(status);
		Log.debug({status:'${status} ${Type.getEnumConstructs(ServerStartupState).indexOf(Type.enumConstructor(status)) + 1} / ${Type.getEnumConstructs(ServerStartupState).length}'});
		if (Type.getEnumConstructs(ServerStartupState).indexOf(Type.enumConstructor(status)) == Type.getEnumConstructs(ServerStartupState).length - 1) {
			Log.info(LogFieldUtil.addServerEvent({}, ServerEventType.READY));
			// Log.info(({}).add(LogEventType.ServerReady));
		}
	}

	inline public function getJobStatusStream() :Stream<JobStatusUpdate>
	{
		var stream = this.getValue('promhx.Stream<JobStatusUpdate>');
		return stream;
	}

	inline public function getRedisClients() :ServerRedisClient
	{
		return this.getValue(ServerRedisClient);
	}

	inline public function getRedisClient() :RedisClient
	{
		var clients :ServerRedisClient = this.getValue(ServerRedisClient);
		return clients.client;
	}

	// inline public function getServiceConfiguration() :ServiceConfiguration
	// {
	// 	var config :ServiceConfiguration = this.getValue('ccc.compute.shared.ServiceConfiguration');
	// 	return config;
	// }

	inline public function getRouter() :ccc.compute.server.execution.routes.RpcRoutes
	{
		var router = this.getValue(ccc.compute.server.execution.routes.RpcRoutes);
		return router;
	}

	inline public function getApplication() :Application
	{
		var app = this.getValue(Application);
		return app;
	}

	inline public function getStorage() :ServiceStorage
	{
		var storage = this.getValue(ServiceStorage);
		return storage;
	}
}