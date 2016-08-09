package ccc.compute;

/**
 * Convenient holder of all the stack subcomponents.
 */

import ccc.compute.workers.*;
import ccc.compute.execution.*;

typedef StackDef = {
	var manager :WorkerManager;
	var provider :WorkerProvider;
	var jobs :Jobs;
}

@:forward
abstract Stack(StackDef)
{
	inline public function new(s :StackDef)
		this = s;

	inline public function dispose() :Promise<Bool>
	{
		return Promise.promise(true)
			.pipe(function(_) {
				return this.jobs != null ? this.jobs.dispose() : Promise.promise(true);
			})
			.pipe(function(_) {
				return this.provider != null ? this.provider.dispose() : Promise.promise(true);
			})
			.pipe(function(_) {
				return this.manager != null ? this.manager.dispose() : Promise.promise(true);
			})
			.then(function(_) {
				this.jobs = null;
				this.provider = null;
				this.manager = null;
				return true;
			});
	}

	@:from
	static public function fromStackDef(s:StackDef)
	{
		return new Stack(s);
	}
}

