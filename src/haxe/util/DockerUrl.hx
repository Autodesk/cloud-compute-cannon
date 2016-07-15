package util;

import t9.abstracts.net.*;

using StringTools;

typedef DockerUrlBlob = {
	var name:String;
	@:optional var username :String;
	@:optional var registryhost :Host;
	@:optional var tag :String;
}

abstract DockerUrl(String) to String from String
{
	inline public function new (s :String)
		this = s;

	public var tag(get, set) :String;
	public var registryhost(get, set) :Host;
	public var username(get, set) :String;
	public var name(get, set) :String;
	public var repository(get, never) :String;

	inline public function noTag() :DockerUrl
	{
		var u = DockerUrlTools.parseDockerUrl(this);
		u.tag = null;
		return DockerUrlTools.joinDockerUrl(u);
	}

	inline public function get_repository() :String
	{
		var u = DockerUrlTools.parseDockerUrl(this);
		u.tag = null;
		u.registryhost = null;
		return DockerUrlTools.joinDockerUrl(u);
	}

	inline public function set_tag(tag :String) :String
	{
		var u = DockerUrlTools.parseDockerUrl(this);
		u.tag = tag;
		this = DockerUrlTools.joinDockerUrl(u);
		return tag;
	}

	inline public function get_tag() :String
	{
		var u = DockerUrlTools.parseDockerUrl(this);
		return u.tag;
	}

	inline public function set_registryhost(registryhost :Host) :Host
	{
		var u = DockerUrlTools.parseDockerUrl(this);
		u.registryhost = registryhost;
		this = DockerUrlTools.joinDockerUrl(u);
		return tag;
	}

	inline public function get_registryhost() :Host
	{
		var u = DockerUrlTools.parseDockerUrl(this);
		return u.registryhost;
	}

	inline public function set_username(username :String) :String
	{
		var u = DockerUrlTools.parseDockerUrl(this);
		u.username = username;
		this = DockerUrlTools.joinDockerUrl(u);
		return tag;
	}

	inline public function get_username() :String
	{
		var u = DockerUrlTools.parseDockerUrl(this);
		return u.username;
	}

	inline public function set_name(name :String) :String
	{
		var u = DockerUrlTools.parseDockerUrl(this);
		u.name = name;
		this = DockerUrlTools.joinDockerUrl(u);
		return tag;
	}

	inline public function get_name() :String
	{
		var u = DockerUrlTools.parseDockerUrl(this);
		return u.name;
	}
}

class DockerUrlTools
{
	public static function matches(a :DockerUrl, b :DockerUrl) :Bool
	{
		if (a.repository == b.repository) {
			var tagA = a.tag;
			var tagB = b.tag;
			return tagA == null || tagB == null ? true : (tagA == tagB);
		} else {
			return false;
		}
	}

	public static function joinDockerUrl(u :DockerUrlBlob, ?includeTag :Bool = true) :String
	{
		return (u.registryhost != null ? u.registryhost + '/' : '')
			+ (u.username != null ? u.username + '/' : '')
			+ u.name
			+ (u.tag != null && includeTag ? ':' + u.tag : '');
	}

	public static function parseDockerUrl(s :String) :DockerUrlBlob
	{
		s = s.trim();
		var r = ~/(.*\/)?([a-z0-9_]+)(:[a-z0-9_]+)?/i;
		r.match(s);
		var registryAndUsername = r.matched(1);
		var name = r.matched(2);
		var tag = r.matched(3);
		if (tag != null) {
			tag = tag.substr(1);
		}
		registryAndUsername = registryAndUsername != null ?registryAndUsername.substr(0, registryAndUsername.length - 1) : null;
		var username :String = null;
		var registryHost :Host = null;
		if (registryAndUsername != null) {
			var tokens = registryAndUsername.split('/');
			if (tokens.length > 1) {
				username = tokens.pop();
				registryHost = tokens.length > 0 ? tokens.join('/') : null;
			} else {
				registryHost = tokens.join('/');
			}
		}
		var url :DockerUrlBlob = {
			name: name
		}
		if (tag != null) {
			url.tag = tag;
		}
		if (username != null) {
			url.username = username;
		}
		if (registryHost != null) {
			url.registryhost = registryHost;
		}
		return url;
	}

	public static function getRepository(u :DockerUrlBlob, ?includeTag :Bool = true) :String
	{
		return (u.registryhost != null ? u.registryhost + '/' : '')
			+ (u.username != null ? u.username + '/' : '')
			+ u.name
			+ (u.tag != null && includeTag ? ':' + u.tag : '');
	}
}