package ccc;

/**
 * Id for a job submitted to the queue
 */
abstract JobId(String) to String from String
{
	inline public function new (s: String)
		this = s;

	inline public function toString() :String
	{
		return this;
	}
}