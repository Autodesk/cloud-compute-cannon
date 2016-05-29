package util;

import haxe.Json;

import promhx.Promise;
import promhx.RequestPromises;

import t9.abstracts.net.*;

using Lambda;

class DockerRegistryTools
{
	public static function getRegistryImages(registry :Host):Promise<Array<String>>
	{
		var url = 'http://$registry/v2/_catalog';
		return RequestPromises.get(url)
			.then(function(out) {
				var data :{repositories:Array<String>} = Json.parse(out);
				return data.repositories;
			});
	}

	public static function getRepositoryTags(registry :Host, repository :String):Promise<Array<String>>
	{
		var url = 'http://$registry/v2/$repository/tags/list';
		return RequestPromises.get(url)
			.then(function(out) {
				var data :{name :String, tags:Array<String>} = Json.parse(out);
				return data.tags;
			});
	}

	public static function isImageIsRegistry(registry :Host, repository :String, tag :String) :Promise<Bool>
	{
		return getRegistryImages(registry)
			.pipe(function(images) {
				if (images.has(repository)) {
					return getRepositoryTags(registry, repository)
						.then(function(tags) {
							return tags.has(tag);
						});
				} else {
					return Promise.promise(false);
				}
			});
	}
}