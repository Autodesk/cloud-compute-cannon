package util;

import haxe.Json;
import haxe.DynamicAccess;

import promhx.Promise;
import promhx.RequestPromises;

import t9.abstracts.net.*;

using Lambda;

class DockerRegistryTools
{
	public static function getRegistryImagesAndTags(registry :Host) :Promise<DynamicAccess<Array<String>>>
	{
		var result = new DynamicAccess<Array<String>>();
		return getRegistryImages(registry)
			.pipe(function(images) {
				var promises = [];
				for (image in images) {
					promises.push(
						getRepositoryTags(registry, image)
							.then(function(tags) {
								result.set(image, tags);
							}));
				}
				return Promise.whenAll(promises)
					.then(function(_) {
						return result;
					});
			});
	}

	public static function getRegistryImages(registry :Host) :Promise<Array<String>>
	{
		return promhx.RetryPromise.retryDecayingInterval(getRegistryImages.bind(registry), 3, 100, 'DockerRegistryTools.getRegistryImages(registry=$registry)');
	}

	public static function __getRegistryImages(registry :Host) :Promise<Array<String>>
	{
		var url = 'http://$registry/v2/_catalog';
		return RequestPromises.get(url)
			.then(function(out) {
				var data :{repositories:Array<String>} = Json.parse(out);
				return data.repositories;
			});
	}

	public static function getRepositoryTags(registry :Host, repository :String) :Promise<Array<String>>
	{
		return promhx.RetryPromise.retryDecayingInterval(__getRepositoryTags.bind(registry, repository), 3, 100, 'DockerRegistryTools.getRepositoryTags(registry=$registry repository=$repository)');
	}

	public static function __getRepositoryTags(registry :Host, repository :String) :Promise<Array<String>>
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