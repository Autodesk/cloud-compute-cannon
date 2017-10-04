package ccc.dashboard.view;

typedef JobsContainerState = JobsState;

class JobsContainer
	extends ReactComponent
{
	public function new()
	{
		super();
	}

	override public function render()
	{
		return jsx('
			<div>
				<JobCardList />
			</div>
		');
	}
}


