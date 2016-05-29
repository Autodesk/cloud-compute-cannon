package js.npm.express;

import EReg;

abstract Route(Dynamic)
 from String to String
  {
 	@:from inline static function fromEReg( e : EReg ) : Route {
 		return untyped e.r;
 	}
}
