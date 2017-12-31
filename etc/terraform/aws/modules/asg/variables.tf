variable "instance_type" {
  default = "t2.micro"
}

variable "s3_access_key" {}
variable "s3_secret_key" {}
variable "s3_region" {}
variable "s3_bucket" {
  default = "cloud-compute-cannon-data"
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

variable "kibana_url" {
  default = ""
}

variable "fluent_port" {
  default = 24224
}

variable "log_level" {
  default = "debug"
}

