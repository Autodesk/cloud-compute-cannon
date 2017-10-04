package ccc.compute.shared.provider;

@:enum
abstract CloudProviderType(String) from String {
	var Local = 'local';
	var AWS = 'aws';
}