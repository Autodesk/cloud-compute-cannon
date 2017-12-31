# Creating a cloud compute stack with terraform

[Terraform](https://www.terraform.io/) provides cluster setup/update/teardown on any configured cloud provider with just a few CLI commands, sometimes just one. Currenly only AWS is supported, although PRs for other providers would be gladly accepted. So follow the link and make sure you have it installed (it's just a binary so there are lots of install options).

## AWS

### Choose your scale, copy config file, add your credentials, and go

There are different options for running a cloud compute stack depending on your use case (see below). Deployment is handled by [Terraform](https://www.terraform.io/) (so install via the link if you do not have it).

Steps:

**Step 1:** Go into the relevant `./examples/` subdirectory, e.g. `./examples/cheapest_scalable_stack`, and copy the file `main.tf` to your computer.

**Step 2:** Create a file called `terraform.tfvars` in the same directory as the `main.tf` file above that contains your AWS credentials and region:

	access_key = "XXX"
	secret_key = "XXXXXXXXX"
	region = "us-east-1"

**Step 3:**

	terraform init
	terraform plan

It should show you the resources about to be created (that you will be billed for!). Then:

	terraform apply

You'll get a promt, follow it, then after all the infrastructure is created and there were no errors, you'll get in the final output a URL for the (cloud compute API)[../../docs/API.md]. Your cloud compute stack is ready to do work for you.

At the end of the `apply` step, there will be an output in green, it is the url for the dashboard and the root [API](../../docs/API.md):

	url = ccc-terraform-elb-542669549.us-east-1.elb.amazonaws.com

**Destroying the stack**

	terraform destroy

That's is! BEWARE: default settings mean your results are deleted (as the S3 bucket is part of the stack, and you are billed for the usage), so make sure you have copied whatever data results from the stack before destroying.

TODO: example how to copy data from S3 to your local disk.

### Available pre-configured stack options (`etc/terraform/aws/examples`)

Pre-configured terraform stack configurations to satisfy different reliability, pricing, speed of setup/teardown requirements.

#### cheapest_scalable_stack

Quick and simple, but scales as much as you need. You need to do a lot of work quickly, but it might be a while before you do work again.

This is meant to be the quickest and cheapest stack that still scales compute nodes. Use it if you want to run a large number of compute jobs quickly, but you are probably not intending to keep the stack around for a long time. It is missing some of the failure handling that a longer running stack requires, so saving some money.

#### TODO: single_node

Simplest, quickest, cheapest, just standard AWS EC2 instance reliability.

If you just want a single compute node, use this config. No scaling, no management, but cheap and quick.

#### TODO: stack_two_availability_zones

Use this stack if you require some level of durability. The smallest stack you should run if you want a reliable and available scalable compute backend job-runner.

The basic stock stack that will run in two amazon availability zones, and the redis cache will have a slave, providing some durability against individual node failure anywhere in the system.

TODO: the logging stack is not as durable.