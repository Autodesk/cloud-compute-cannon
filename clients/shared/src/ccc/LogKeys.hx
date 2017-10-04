package ccc;
/**
 * Keys for logs. This is effectively a list of keys to look for
 * when searching kibana.
 */

@:enum
abstract LogKeys(String) {
	var stack = 'stack';
	var workerevent = 'workerevent';
	var serverevent = 'serverevent';
	var jobevent = 'jobevent';
}
