package ccc.dashboard.view;

typedef WorkerViewProps = {
	workerId:MachineId,
	worker:Dynamic
}

class WorkerView
	extends ReactComponentOfProps<WorkerViewProps>
{
	public function new(props :WorkerViewProps)
	{
		super(props);
	}

	override public function render()
	{
		var styles = {
			parent: {
				flex: "1 0 auto", //flex-grow, flex-shrink, flex-basis
				border: "5px solid red",
#if css_colors
				background: "AliceBlue",
#end
			}
		};

		var id = props.workerId;
		var def = props.worker;
		return jsx('
			<div style={styles.parent} >
				<p>{id}</p>
				<p>definition=${Json.stringify(def)}</p>
				<Paper zDepth={2}>
					{id}
				</Paper>
			</div>
		');
	}
}
