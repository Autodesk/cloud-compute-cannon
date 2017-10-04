package ccc.dashboard.view;

import router.Link;
import router.RouteComponentProps;

import js.npm.reactdnd.ReactDnd;
import js.npm.reactdnd.ReactDnd.HTML5Backend;
import js.npm.reactdnd.ReactDnd.DragDropContextProvider;

class AppView
	extends ReactComponentOfPropsAndState<RouteComponentProps, Dynamic>
	implements IConnectedComponent

{
	public function new(props:RouteComponentProps)
	{
		super(props);
	}

	function mapState(appState:ApplicationState, props:RouteComponentProps)
	{
		return assign({}, [state]);
	}

	override public function render()
	{
		var styles = {
			dragParent: {
				width: "100px",
				height: "100px",
				backgroundColor: "yellow"
			},
			parent: {
				flex: "1 0 auto",
				display: "flex",
				flexDirection: "row",
				// width: "100%",
				// backgroundColor: "green"
			},
			leftContainer: {
				flex: "0 1 auto",
				display: "flex",
				flexDirection: "column",
				// width: "100%",
#if css_colors
				backgroundColor: "purple"
#end
			},
			rightContainer: {
				flex: "1 0 auto",
				display: "flex",
				flexDirection: "column",
				// width: "100%",
#if css_colors
				backgroundColor: "cyan"
#end
			}
		};
		//<JobsDebugView />
		var testJobCard = JobCard.example();
		// <div style={{minHeight="160px"}}>
		// </div>
		return jsx('
			<DragDropContextProvider backend={HTML5Backend}>
				<div style={styles.parent}>
					<div style={styles.leftContainer}>
					</div>
					<div style={styles.rightContainer}>
						<WorkersListView />
						<JobsContainer />
					</div>
					{testJobCard}
				</div>
			</DragDropContextProvider>
		');
	}
}
