package ccc.dashboard.view;

import js.npm.reactvirtualized.AutoSizer;

typedef JobCardListState = {
	var items :Array<JobId>;
	var jobs :TypedDynamicAccess<JobId, JobStatsData>;
	var active :Array<JobId>;
	var finished :Array<JobId>;
};

typedef JobCardListProps = {
};

class JobCardList
	extends ReactComponentOfPropsAndState<JobCardListProps, JobCardListState>
	implements IConnectedComponent
{
	public static var initState :JobCardListState = {
		items: [],
		jobs: {},
		active: [],
		finished: []
	};

	public function new(props :JobCardListProps)
	{
		super(props);
		state = initState;
	}

	function mapState(appState:ApplicationState, ?ignored :Dynamic)
	{
		var jobState = appState.app.jobs;
		//Quickly detect if the list of jobIds (ordered) is different
		var newJobIds = null;
		if (state.active != jobState.active || state.finished != jobState.finished) {
			newJobIds = jobState.active.concat(jobState.finished);
		}
		var newJobMap = null;
		if (state.jobs != jobState.all) {
			newJobMap = jobState.all;
		}
		if (newJobIds != null || newJobMap != null) {
			return {
				items: newJobIds == null ? state.items : newJobIds,
				jobs: newJobMap == null ? state.jobs: newJobMap,
				active: jobState.active,
				finished: jobState.finished
			}
		} else {
			return state;
		}
	}

	override public function render()
	{
		//Adding the items prop was the only way I could get
		//rendering children to work after updating a single
		//entry in the state.items object
		return jsx('
			<AutoSizer items={state.items}>
				{renderGridList}
			</AutoSizer>
		');
	}

	function renderGridList(opts :{width :Int, height :Int})
	{
		var cellHeight = 100;
		var cellPadding = 1;
		var height = opts.height == 0 ? 300 : opts.height;
		var items = state.items;
		if (items == null) {
			items = [];
		}
		height = Std.int(Math.min(height, items.length * cellHeight + (items.length + 1) * cellPadding));
		var width = opts.width == 0 ? 300 : opts.width;

		var styles = {
			gridList: {
				width: width,
				height: height,
				overflowY: 'auto',
				 justifyContent: 'flex-start',
#if css_colors
				backgroundColor: "blue"
#end
			},
		};
		// trace('itemss duplicates? ${items.containsDuplicates()}');

		items = items.filter(function(id) {
			return state.jobs.exists(id);
		});
		var children = items.map(tileRenderer);
		return jsx('
				<GridList
					cols={1}
					cellHeight={cellHeight}
					padding={cellPadding}
					width={width}
					height={height}
					style={styles.gridList}
				>
					${children}
				</GridList>
		');
	}

	function tileRenderer(id :JobId)
	{
		var item :JobStatsData = this.state.jobs.get(id);
		return jsx('
			<JobCard key={id} id={id} item={item} />
		');
	}
}
