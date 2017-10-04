package ccc;

/**
 * I'm expecting this typedef to include:
 * memory contraints
 * CPU/GPU constraints
 * storage constraints
 */
typedef JobParams = {
	var maxDuration :Int;//Seconds
	var cpus :Int;
}