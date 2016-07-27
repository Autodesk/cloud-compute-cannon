package compute;

import batcher.cli.ProviderTools;
import batcher.cli.ProviderTools.*;

import js.Node;
import js.node.ChildProcess;
import js.node.Os;
import js.node.Path;

import js.npm.fsextended.FsExtended;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

import utils.TestTools;

import t9.abstracts.net.Host;

using promhx.PromiseTools;

class TestCLIRemoteServerInstallation extends TestComputeBase
{
	public function testInstallServerOnNewInstance()
	{
		//Prefer (in order) AWS, Vagrant, just local Docker
		//Install server
		//Server URL check
		//Perform job, check job outputs
	}

	public function new() {}
}