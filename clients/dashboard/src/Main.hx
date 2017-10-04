import ccc.dashboard.view.AppView;
import ccc.dashboard.ApplicationState;
import ccc.dashboard.ApplicationStore;

import js.Browser;
import js.html.DivElement;
import js.npm.materialui.MaterialUI;

import react.ReactDOM;
import react.ReactMacro.jsx;

import redux.Store;
import redux.react.Provider;

import router.Link;
import router.ReactRouter;
import router.RouteComponentProps;

class Main
{
	/**
		Entry point:
		- setup redux store
		- setup react rendering
		- send a few test messages
	**/
	public static function main()
	{
		new js.npm.reacttapeventplugin.ReactTapEventPlugin();
		var store = ApplicationStore.create();
		var root = createRoot();
		render(root, store);

		ApplicationStore.startup(store);
	}

	static function createRoot()
	{
		var root = Browser.document.createDivElement();
		Browser.document.body.appendChild(root);
		return root;
	}

	static function render(root:DivElement, store:Store<ApplicationState>)
	{
		var history = ReactRouter.browserHistory;

		var app = ReactDOM.render(jsx('

			<MuiThemeProvider>
				<Provider store=$store>
					<AppView/>
				</Provider>
			</MuiThemeProvider>

		'), root);
		//<Route path="gallery" getComponent=${RouteBundle.load(GalleryView)}/>

		#if (debug && react_hot)
		ReactHMR.autoRefresh(app);
		#end
	}

	static function pageWrapper(props:RouteComponentProps)
	{
		var mainDivStyle = {
			height: "100%",
			display: "flex",
			flexDirection: "column",
			minHeight: "100vh"
		}
		return jsx('
			<div style={mainDivStyle}>
				${props.children}
			</div>
		');
	}
}
