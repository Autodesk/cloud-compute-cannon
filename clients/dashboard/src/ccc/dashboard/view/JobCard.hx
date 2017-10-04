package ccc.dashboard.view;

import js.npm.reacttable.ReactTable;

typedef JobCardProps = {
	var item :JobStatsData;
	var id :JobId;
}

typedef JobCardState = {
	var expanded :Bool;
}

class JobCard
	extends ReactComponentOfPropsAndState<JobCardProps, JobCardState>
{
	public static var initState :JobCardState = {
		expanded: false
	};

	public function new(props :JobCardProps)
	{
		super(props);
		state = initState;
	}

	override public function shouldComponentUpdate(nextProps :JobCardProps, nextState :JobCardState)
	{
		return props.item == null || props.id != nextProps.id || props.item.v < nextProps.item.v || nextState.expanded != this.state.expanded;
	}

	override public function render()
	{
		var name = props.item.def != null && props.item.def.meta != null && props.item.def.meta.name != null ? props.item.def.meta.name : props.id;
		var id = props.id;
		var stats = props.item;

		var data :Array<{name:String, value:Dynamic}> = [
			{
				name: 'duration',
				value: DateFormatTools.getShortStringOfDateDiff(Date.fromTime(stats.requestReceived), Date.fromTime(stats.finished))
			},
			{
				name: 'recieved',
				value: DateFormatTools.getFormattedDate(stats.requestReceived)
			},
			{
				name: 'attempts',
				value: stats.attempts != null ? stats.attempts.length : 'unknown'
			},
		];

		var columns = [
			{
				Header: 'Name',
				accessor: 'name' // String-based value accessors! 
			},
			{
				Header: 'Value',
				accessor: 'value',
				// Cell: props => <span className='number'>{props.value}</span> // Custom cell components! 
			},
			// {
			// 	id: 'friendName', // Required because our accessor is not a string 
			// 	Header: 'Friend Name',
			// 	accessor: d => d.friend.name // Custom value accessors! 
			// },
			// {
			// 	Header: props => <span>Friend Age</span>, // Custom header components! 
			// 	accessor: 'friend.age'
			// }
		];

		// https://www.npmjs.com/package/react-table
		var pageSize = data.length;

		var dataContent = if (state.expanded) {
			jsx('
				<ReactTable
					data={data}
					columns={columns}
					showPagination={false}
					defaultPageSize={pageSize}
					showPageJump={false}
					sortable={false}
					resizable={false}
					style={{fontSize:"6px"}}
				/>
			');
		} else {
			jsx('
				<div>
					Not expanded
				</div>
			');
		}

		var isToggled = state.expanded;

		return jsx('
				<Paper key={id} className="jobcard">
					Job: {name}
					<Toggle
						label="Expand"
						defaultToggled={false}
						toggled={isToggled}
						onToggle={toggleExpansion}
					/>
					{dataContent}
				</Paper>
			');


		// var rows :Array<ReactElement> = data.mapi(function(index, row) {
		// 	return jsx('
		// 		<TableRow key={index} className="jobcard-tablerow" style={{height:"10px"}}>
		// 			<TableRowColumn className="jobcard-tablerowcolumn" style={{height:"10px"}}>{row.name}</TableRowColumn>
		// 			<TableRowColumn className="jobcard-tablerowcolumn" style={{height:"10px"}}>{row.value}</TableRowColumn>
		// 		</TableRow>
		// 	');
		// }).array();

		// return jsx('
		// 	<Paper key={id} className="jobcard">
		// 		Job: {name}
		// 		<Table
		// 			fixedHeader={false}
		// 			fixedFooter={false}
		// 			selectable={false}
		// 			multiSelectable={false}
		// 			className="jobcard-table"
		// 		>
		// 			<TableHeader
		// 				displaySelectAll={false}
		// 				adjustForCheckbox={true}
		// 				enableSelectAll={false}
		// 			>
		// 				<TableRow>
		// 					<TableHeaderColumn colSpan="3" tooltip="Super Header" style={{textAlign: "center", height:"10px"}}>
		// 						Super Header
		// 					</TableHeaderColumn>
		// 				</TableRow>
		// 			</TableHeader>
		// 			<TableBody
		// 				displayRowCheckbox={false}
		// 				deselectOnClickaway={false}
		// 				showRowHover={false}
		// 				stripedRows={true}
		// 			>
		// 				{rows}
		// 			</TableBody>
		// 		</Table>
		// 	</Paper>
		// ');
	}

	function toggleExpansion()
	{
		setState({expanded:!state.expanded});
	}

	public static function example() {
		var now = Date.now().getTime();
		var id = 'testId';
		var item :JobStatsData = {
			v: 1,
			jobId: 'ExampleJobId',
			requestReceived: now - 100000,
			requestUploaded: now -  90000,
			attempts: [
				{
					worker: new MachineId('testworker'),
					enqueued: now - (90000 - 1000),
					dequeued: now - (90000 - 2000),
					copiedInputs: 0,
					copiedOutputs: 0,
					copiedLogs: 0,
					copiedImage: 0,
					copiedInputsAndImage: 0,
					containerExited: 0,
					exitCode: 0,
					statusWorking: JobWorkingStatus.FinishedWorking,
				}
			],
			finished: now - 7000,
			def: {

			},
			status: JobStatus.Finished,
			statusFinished: JobFinishedStatus.Success,
			statusWorking: JobWorkingStatus.FinishedWorking,
			error: null,
		};


		return jsx('
			<JobCard key={id} id={id} item={item} />
		');
	}
}
