package ccc;

abstract MachineId(String) to String from String
{
	inline public function new (s: String)
	{
		this = s;
	}
}