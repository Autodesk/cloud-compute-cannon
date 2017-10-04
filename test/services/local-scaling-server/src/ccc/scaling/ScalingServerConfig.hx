package ccc.scaling;

@:build(util.NodejsMacros.addProcessEnvVars())
class ScalingServerConfig
{
	@NodeProcessVar
	public static var PORT :Int = 4015;

	@NodeProcessVar
	public static var REDIS_HOST :String = 'redis';

	@NodeProcessVar
	public static var REDIS_PORT :Int = 6379;

	/**
	 * CCC address for hitting the API
	 */
	@NodeProcessVar
	public static var CCC :String;

	public static function toJson() :Dynamic
	{
		return {
			'PORT': PORT,
			'REDIS_HOST': REDIS_HOST,
			'REDIS_PORT': REDIS_PORT,
			'CCC': CCC,
		};
	}
}