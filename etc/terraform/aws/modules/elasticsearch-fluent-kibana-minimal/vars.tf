variable "region" {
  description = "AWS region"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "vpc_id" {}

# variable "vpc_security_group_ids" {}

variable "subnet_id" {}

variable "key_name" {}
