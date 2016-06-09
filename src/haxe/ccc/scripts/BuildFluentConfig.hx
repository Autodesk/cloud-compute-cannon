package ccc.scripts;

import haxe.Template;
import sys.io.File;

/**
 * Build fluent config from templates.
 */
class BuildFluentConfig
{
	static function main()
	{
		for (type in ['dev', 'prod']) {
			var base = 'etc/log/fluent.conf.base.template';
			var baseContent = new Template(File.getContent(base)).execute(ccc.compute.Definitions.Constants);
			var inFile = 'etc/log/fluent.$type.conf.template';
			var inContent = File.getContent(inFile);
			var outContent = new Template(inContent).execute(ccc.compute.Definitions.Constants);
			File.saveContent('etc/log/fluent.$type.conf', baseContent + outContent);
		}
	}
}