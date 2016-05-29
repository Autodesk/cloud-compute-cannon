package util;

import haxe.macro.Context;
import haxe.macro.Expr;

class CopyMethods {	

	static function toIdentifier( verb : String ) {
		var r = ~/[^a-zA-Z0-9_]+/g;
		var v = verb;

		if( !r.match(v) ){
			return v;
		}

		var id = r.matchedLeft();
		v = r.matchedRight();

		while( r.match(v) ){
			var term = r.matchedLeft();
			id += term.substr(0,1).toUpperCase() + term.substr(1);
			v = r.matchedRight();		
		}

		var term = v;
		id += term.substr(0,1).toUpperCase() + term.substr(1);

		return id;
	}

	static macro function build( verbs : ExprOf<Array<String>> , _fun : ExprOf<Function> , overloads : ExprOf<Array<Function>> ) : Array<Field> {
		var fields = Context.getBuildFields();

		var fun = switch( _fun.expr ){
			case EFunction(null, f) : 
				f;
			case _ : throw 'unsupported';
		}
		
		switch(verbs.expr){
			case EArrayDecl(arr) : 
				for( s in arr ) {
					switch( s.expr ) {
						case EConst(CString( verb )) : 
							
							var method = toIdentifier( verb );

							var f = {
								name : method,
								pos : s.pos,
								kind : FFun(fun),
								meta : [],
								access : []
							};

							if( method != verb ) {
								f.access.push(AInline);
								fun.expr = macro untyped return this[$v{verb}]( path , f );
							}
							switch( overloads.expr ){
								case EArrayDecl(arr2) : 
									for( o in arr2 ) {
										f.meta.push({
											pos : o.pos,
											params : [o],
											name : ":overload"
										});
									}
								case _ : throw 'assert';

							}
							fields.push(f);
						case _ : throw 'assert';
					}
				}
			case _ : throw 'assert';

		}
		
		return fields;
	}
}
