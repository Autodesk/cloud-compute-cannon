package ccc.dashboard.view;

import redux.StoreMethods;

typedef JobsDebugViewProps = {
	workerId:MachineId,
	worker:Dynamic
}

class JobsDebugView
	extends ReactComponentOfPropsAndState<JobsDebugViewProps, JobsState>
	implements IConnectedComponent
{
	public var initState :JobsState = {
		all: {},
		active: [],
		finished: []
	};

	public var store :StoreMethods<ApplicationState>;

	public function new(props :JobsDebugViewProps)
	{
		super(props);
	}

	function mapState(appState:ApplicationState, props:JobsDebugViewProps)
	{
		return assign({}, [appState.app.jobs]);
	}

	override public function render()
	{
		var styles = {
			parent: {
				flex: "1 0 auto", //flex-grow, flex-shrink, flex-basis
				border: "5px solid green",
#if css_colors
				background: "AliceBlue",
#end
			}
		};

		var jobIds = state.active == null ? [] : state.active;
		var listItems = jobIds.map(function(jobId) {
			var item = state.all.get(jobId);
			var name = jobId;
			if (item.def != null && item.def.meta != null && item.def.meta.name != null) {
				name = item.def.meta.name;
			}
			return jsx('
				<ListItem key="$jobId" primaryText="$name">
				</ListItem>
			');
		});

		return jsx('
			<div style={styles.parent} >
				<List >
					{listItems}
				</List>
			</div>
		');
	}
}
