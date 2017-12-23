variable "instance_type" {
  default = "t2.micro"
}

variable "key_name" {}

variable "subnets" {
  type = "list"
}

variable "region" {
  description = "AWS region"
}

# variable "availability_zones" {
#   type = "list"
# }

variable "vpc_id" {}

# variable "vpc_zone_identifier" {
#   type = "list"
# }

variable "max_size" {
  default = 4
}

variable "min_size" {
  default = 1
}

variable "redis_host" {}

variable "redis_security_group_id" {}

variable "fluent_host" {
  default = ""
}

variable "fluent_port" {
  default = 24224
}

variable "log_level" {
  default = "debug"
}

# output "name" {
#   value = "${aws_autoscaling_group.asg_worker.name}"
# }