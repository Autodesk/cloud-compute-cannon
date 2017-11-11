## Devops requirements for CCC cloudformation:

CCC requires three parts to install:

 1. Autoscaling Lambdas
 2. Redis cache
 3. CCC worker stack

### Autoscaling Lambdas

<<<<<<< HEAD
**Before** uploading lambdas, ensure that they at least run correctly in a simulated AWS runtime:

	./bin/lambdas-validate

This *will* produce some errors, e.g. "The security token included in the request is invalid". This is good! It means the script has loaded the necessary npm modules, and started up ok. If you see different errors, or no initial log of "LambdaScalingAws.hx:40: handlerScaleUp" then you may have issues with packaging the script, and it will likely NOT work in AWS.

If that looks good then bump the version in `etc/bionano/aws/cloudformation/lambda-autoscaling/src/package.json`.

Then test packaging up the lambdas for deployment in AWS:

	cd etc/bionano/aws/cloudformation/lambda-autoscaling
	./deploy --dryrun -k <AWS_ACCESS_KEY_ID> -s <AWS_SECRET_ACCESS_KEY> -t <dev|qa|prod> -n <subnet1,subnet2,...> -g <security group id>

If that looks good, remove the `--dryrun` flag to actually upload to AWS.

**IMPORTANT**

After you have deloyed the AWS lambda functions, go into the lambda tab in the AWS panel (https://us-west-2.console.aws.amazon.com/lambda/home?region=us-west-2#/functions -> Lambda name -> Monitoring -> View logs in Cloudwatch) and inspect the logs of the new lambdas. They should output various log statements and no errors. If you see errors


#### Autoscaling Lambdas Notes

To get the autoscaling group the lambda searches for a tag (that starts with):

	stack=<BNR_ENVIRONMENT>-ccc*

The lambda also assumes that a redis cluster can be found at:

	redis.<BNR_ENVIRONMENT>.bionano.bio


### Redis cache

The Cloudformation script creates the redis cluster, and associates the HostRecord for the internal DNS name

	cd etc/bionano/aws/cloudformation/redis
	./deploy -k <AWS_ACCESS_KEY_ID> -s <AWS_SECRET_ACCESS_KEY> -t <dev|qa|prod>

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
