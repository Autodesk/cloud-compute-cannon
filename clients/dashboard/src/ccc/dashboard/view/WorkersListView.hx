package ccc.dashboard.view;

import router.Link;
import router.RouteComponentProps;

typedef WorkersListViewState = { >WorkersState,
}

typedef WorkersListViewProps = {
}

class WorkersListView
	extends ReactComponentOfPropsAndState<WorkersListViewProps, WorkersListViewState>
	implements IConnectedComponent
{
	public function new(props:WorkersListViewProps)
	{
		super(props);
		state = { workers: {} };
	}

	function mapState(appState:ApplicationState, ?ignored :Dynamic)
	{
		if (appState.app != null && appState.app.workers != null && appState.app.workers.workers == this.state.workers) {
			return this.state;
		}
		var workersList = appState.app != null && appState.app.workers != null ? appState.app.workers.workers : null;
		return assign({}, [this.state, { workers: assign({}, [workersList]) }] );
	}

	override public function render()
	{
		var workers = state.workers;

		var styles = {
			root: {
				flex: "1 0 auto",
#if css_colors
				backgroundColor: "aqua",
#end
			}
		};
		var buttonRight = jsx('<FlatButton label="+" />');

		var children = workers == null ? [] : workers.keys().array().map(function(workerId) {
			var definition = workers.get(workerId);
			return jsx('
					<WorkerView
						key={workerId}
						workerId={workerId}
						worker={definition}
					/>
				');
		});
		return jsx('
				<div style={styles.root}>
					<AppBar
						title={"sometimtl"}
						iconElementRight={buttonRight}
					>
					</AppBar>
					${children}
				</div>
		');
	}
}
