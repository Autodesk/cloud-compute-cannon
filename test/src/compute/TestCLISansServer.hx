package compute;

import batcher.cli.ProviderTools;
import batcher.cli.ProviderTools.*;
import batcher.cli.CliTools.*;

import js.Node;
import js.node.ChildProcess;
import js.node.Os;
import js.node.Path;

import js.npm.FsExtended;

import promhx.Promise;
import promhx.deferred.DeferredPromise;

import utils.TestTools;

import t9.abstracts.net.Host;

using promhx.PromiseTools;

class TestCLISansServer extends TestComputeBase
{
	/**
	 * Tests getting the correct server config blob in the
	 * file system heirarchy.
	 * @return [description]
	 */
	public function testGetServerConfigPath()
	{
		var TESTROOT = 'tmp/testGetServerConfigPath';
		var HOMEDIR = untyped __js__('require("os").homedir()');

		var fakeServerConfig :ServerConnectionBlob = {
			server: {
				ssh: {
					host: 'fakehost',
					username: 'fakeusername'
				},
				docker: {}
			}
		}

		var serverConfigPath1 = Path.join(TESTROOT, '/foo/bar/');
		var serverConfigPath2 = Path.join(TESTROOT);

		FsExtended.deleteDirSync(TESTROOT);

		FsExtended.ensureDirSync(serverConfigPath1);
		FsExtended.ensureDirSync(serverConfigPath2);

		assertEquals(findExistingServerConfigPath(TESTROOT), null);
		assertEquals(findExistingServerConfigPath(serverConfigPath1), null);
		assertEquals(findExistingServerConfigPath(serverConfigPath2), null);

		assertNotNull(haxe.Resource.getString('etc/config/serverconfig.template.yaml'));

		//Write the files, make sure we get the closest
		writeServerConnection(serverConfigPath2, fakeServerConfig);
		assertEquals(findExistingServerConfigPath(serverConfigPath1), Path.join(Node.process.cwd(), serverConfigPath2));
		assertEquals(findExistingServerConfigPath(serverConfigPath2), Path.join(Node.process.cwd(), serverConfigPath2));

		writeServerConnection(serverConfigPath1, fakeServerConfig);
		assertEquals(findExistingServerConfigPath(serverConfigPath1), Path.join(Node.process.cwd(), serverConfigPath1));
		assertEquals(findExistingServerConfigPath(serverConfigPath2), Path.join(Node.process.cwd(), serverConfigPath2));

		return getServerHost(serverConfigPath1)
			.then(function(host) {
				assertNotNull(host);
				assertEquals(host, fakeServerConfig.server.ssh.host + ':' + Constants.SERVER_DEFAULT_PORT);
				return true;
			});
	}

	public function new() {}
}