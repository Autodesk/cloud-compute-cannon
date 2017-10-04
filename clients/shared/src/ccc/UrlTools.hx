package ccc;
/**
 * A single place to get the various CCC proxy, RPC, and storage request URLs
 */

import t9.abstracts.net.*;

using StringTools;

class UrlTools
{
	static var DEFAULT_PROTOCOL = 'http';
	// static var SERVER_LOCAL_RPC_URL :UrlString = '${DEFAULT_PROTOCOL}://${SERVER_LOCAL_HOST}${SERVER_RPC_URL}';
	static var CURRENT_VERSION :String = '${Type.enumConstructor(CCCVersion.v1)}';

	inline public static function rpcUrl(base :Host) :UrlString
	{
		return '${DEFAULT_PROTOCOL}://${base}${base.endsWith("/") ? "" : "/"}${CURRENT_VERSION}';
	}
}
