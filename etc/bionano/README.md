## Devops requirements for CCC cloudformation:

CCC requires three parts to install:

 1. Redis cache
 2. Autoscaling Lambdas
 3. CCC worker stack

### Redis cache

The Cloudformation script creates the redis cluster, and associates the HostRecord for the internal DNS name

	cd etc/bionano/aws/cloudformation/redis
	./deploy -k <AWS_ACCESS_KEY_ID> -s <AWS_SECRET_ACCESS_KEY> -t <dev|qa|prod>

### Autoscaling Lambdas

This will package up the lambdas and deploy them in the region:

	cd etc/bionano/aws/cloudformation/lambda-autoscaling
	./deploy -k <AWS_ACCESS_KEY_ID> -s <AWS_SECRET_ACCESS_KEY> -t <dev|qa|prod>

To get the autoscaling group the lambda searches for a tag (that starts with):

	stack=<BNR_ENVIRONMENT>-ccc*

The lambda also assumes that a redis cluster can be found at:

	redis.<BNR_ENVIRONMENT>.bionano.bio

### CCC worker stack

This uses the standard docker-jenkins based builds, except that the CCC lambdas control the autoscaling.

 - Set `AutoscaleThreshold` param to `none` when updating CCC stack in CloudFormation (otherwise this will conflict with the lambas, and workers that are executing long-running jobs can be killed).
 - Autoscaling groups must be tagged for lambda to find them (currently using the hard coded name).
 - The docker-compose file used for running in the bionano Autoscaling groups is `etc/bionano/aws/docker/docker-compose-aws.yml`.

### Health checks

Curl:

	<ccc host>:9000/test

The result is a 200 response if the check succeeds.

The health check runs a small job on a priority queue, so should return pretty fast, and can be run quite often (every minute or couple of minutes).
