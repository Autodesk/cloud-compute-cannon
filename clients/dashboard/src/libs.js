//
// npm dependencies library
//
(function(scope) {
	'use-strict';
	scope.__registry__ = Object.assign({}, scope.__registry__, {

		// list npm modules required in Haxe

		'moment-timezone': require('moment-timezone'),
		'react': require('react'),
		'react-dom': require('react-dom'),
		'react-router': require('react-router'),
		'redux': require('redux'),
		'react-virtualized': require('react-virtualized'),
		'redux-logger': require('redux-logger'),
		'material-ui': require('material-ui'),
		'react-tap-event-plugin': require('react-tap-event-plugin'),
		'react-infinite': require('react-infinite'),
		'react-dnd': require('react-dnd'),
		'react-dnd-html5-backend': require('react-dnd-html5-backend'),
		'react-table': require('react-table'),
	});

	if (process.env.NODE_ENV !== 'production') {
		// enable hot-reload
		require('haxe-modular');
	}

})(typeof $hx_scope != "undefined" ? $hx_scope : $hx_scope = {});
