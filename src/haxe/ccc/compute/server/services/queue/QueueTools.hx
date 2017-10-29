package ccc.compute.server.services.queue;

import ccc.QueueJobDefinition;
import ccc.compute.worker.QueueJobs;
import ccc.compute.worker.QueueJobResults;

import js.npm.bull.Bull;

class QueueTools
{
	public static function initJobQueue(injector :Injector)
	{
		var redisHost :String = ServerConfig.REDIS_HOST;
		var redisPort :Int = ServerConfig.REDIS_PORT;
		var queueName :String = BullQueueNames.JobQueue;
		var queue : js.npm.bull.Bull.Queue<QueueJobDefinition,QueueJobResults> = new js.npm.bull.Bull.Queue(queueName, {redis:{port:redisPort, host:redisHost}});
		// Notice the space and the specific package names.
		// minject cannot handle classes with parameters unless you use
		// strings, but the strings must be exactly formatted.
		injector.map('js.npm.bull.Queue<ccc.QueueJobDefinition, ccc.compute.worker.QueueJobResults>').toValue(queue);
	}

	public static function addJobToQueue(queue :Queue<QueueJobDefinition, QueueJobResults>, job :QueueJobDefinition, ?log :AbstractLogger) :Promise<Bool>
	{
		log = log == null ? Log.log : log;
		job.attempt = 1;
		return switch(job.type) {
			case compute:
				Promise.promise(true)
					.pipe(function(_) {
						var def :DockerBatchComputeJob = job.item;
						log.info(LogFieldUtil.addJobEvent({jobId:job.id, attempt:1, type:job.type, message:'via ProcessQueue', meta: def.meta}, JobEventType.ENQUEUED));

						return Promise.whenAll([
							Jobs.setJob(job.id, job.item),
							Jobs.setJobParameters(job.id, job.parameters),
							JobStatsTools.jobEnqueued(job.id, job.item)
								.thenTrue()
						]);
					})
					.then(function(_) {
						queue.add(job, {jobId:job.id, priority:(job.priority ? 1 : 1000), removeOnComplete:true, removeOnFail:true});
						return true;
					});
			case turbo:
				var def :BatchProcessRequestTurboV2 = job.item;
				log.info(LogFieldUtil.addJobEvent({jobId:job.id, attempt:1, type:job.type, message:'via ProcessQueue', meta: def.meta}, JobEventType.ENQUEUED));
				var maxTime = 300000;//5 minutes max
				queue.add(job, {jobId:job.id, priority:1, removeOnComplete:true, removeOnFail:true, timeout:maxTime});
				Promise.promise(true);
		}
	}

	public static function addBullDashboard(injector :Injector)
	{
		var redisHost :String = ServerConfig.REDIS_HOST;
		var redisPort :Int = ServerConfig.REDIS_PORT;
		var bullArena = new js.npm.bullarena.BullArena(
			{
				queues:[
					{
						name: BullQueueNames.JobQueue,
						port: redisPort,
						host: redisHost,
						hostId: redisHost
					},
					{
						name: BullQueueNames.SingleMessageQueue,
						port: redisPort,
						host: redisHost,
						hostId: redisHost
					}
				]
			},
			{
				basePath: '/dashboard',
				disableListen: true
			}
		);

		var app :js.npm.express.Application = injector.getValue(js.npm.express.Application);
		var router = js.npm.express.Express.GetRouter();
		router.use('/', cast bullArena);
		app.use(cast router);
	}
}