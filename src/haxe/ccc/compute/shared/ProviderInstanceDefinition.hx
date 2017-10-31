package ccc.compute.shared;

typedef ProviderInstanceDefinition = {
	/* Workers typically are not exposed to the internet, while servers are */
	@:optional var public_ip :Bool;
	/* Not all platforms support tagging */
	@:optional var tags :DynamicAccess<String>;
	/* These are specific to the provider e.g. AWS */
	@:optional var options :Dynamic;
	/* SSH key for this machine. May be defined in parent (shared with other definitions) */
	@:optional var key :String;
}
