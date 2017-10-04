package ccc;

@:enum
abstract BullQueueNames(String) from String to String {
	var JobQueue = 'job_queue';
	/* Any worker can process this message */
	var SingleMessageQueue = 'single_message_queue';
}
