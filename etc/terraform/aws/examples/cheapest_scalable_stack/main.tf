provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = "${var.public_key}"
}

# Declare the data source
data "aws_availability_zones" "available" {}

#All the stuff, high level
# redis module
# lambda autoscaling module
# ccc asg module

#VPC
module "vpc" {
  source = "github.com/terraform-aws-modules/terraform-aws-vpc?ref=master"

  name = "ccc-vpc"
  cidr = "10.0.0.0/16"

  azs  = ["${data.aws_availability_zones.available.names[0]}"]

  create_database_subnet_group = false

  private_subnets = ["10.0.1.0/24"]
  public_subnets  = ["10.0.101.0/24"]
  enable_nat_gateway = true
  enable_vpn_gateway = true
  single_nat_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
    System = "ccc"
  }
}

#Redis
module "redis" {
  source  = "${path.module}/../../modules/redis/minimal"
  region = "${var.region}"
  vpc_id = "${module.vpc.vpc_id}"
  subnet_id = "${module.vpc.public_subnets[0]}"
  key_name = "${aws_key_pair.deployer.key_name}"
  instance_type = "t2.micro"
}

# Autoscaling Group
module "asg" {
  source  = "${path.module}/../../modules/asg"
  # Verify this
  redis_security_group_id = "${module.redis.security_group_id}"
  key_name = "${aws_key_pair.deployer.key_name}"
  vpc_id = "${module.vpc.vpc_id}"
  subnets = ["${concat("${module.vpc.public_subnets}")}"]
  instance_type = "t2.micro"
  region = "${var.region}"
  redis_host = "${module.redis.hostname}"
  fluent_host = "${module.elk.hostname}"
}

#Lambda scaling
module "lambda" {
  source  = "${path.module}/../../modules/lambdas"
  subnet_ids = ["${concat("${module.vpc.public_subnets}", "${module.vpc.private_subnets}")}"]
  security_group_ids = ["${module.redis.security_group_id}"]
  redis_host = "${module.redis.hostname}"
  asg_name = "${module.asg.name}"
}

#ELK stack (logging)
module "elk" {
  source  = "${path.module}/../../modules/elasticsearch-fluent-kibana-minimal"
  region = "${var.region}"
  vpc_id = "${module.vpc.vpc_id}"
  subnet_id = "${module.vpc.public_subnets[0]}"
  key_name = "${aws_key_pair.deployer.key_name}"
  instance_type = "t2.micro"
}

output "kibana" {
  value = "${module.elk.hostname}"
}

output "url" {
  value = "${module.asg.url}"
}