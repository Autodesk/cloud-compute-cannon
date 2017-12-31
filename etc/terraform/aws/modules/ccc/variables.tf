variable "s3_access_key" {}
variable "s3_secret_key" {}

variable "single_node" {
  description = "Is this cloud compute just a single node? This is fast and cheap, as a lot of infrastructure is not created"
  default = false
}

variable "s3" {
  description = "Use a S3 bucket for durable storage. This is still destroyed when the stack is destroyed, so make sure you backup."
  default = true
}

variable "multi-zone" {
  description = "If multi-zone, more durable (and expensive) components are created. For instance, a dedicated elasticache type is used instead of just an instance with redis running"
  default = false
}



# locals {
#   ccc_type_single_node = "ccc_type_single_node"
#   ccc_type_single_node_s3 = "ccc_type_single_node_s3"
#   ccc_type_multi_node_quick = "ccc_type_multi_node_quick"
#   ccc_type_multi_node_durable = "ccc_type_multi_node_durable"
# }

# #Allowed type value:
# # ccc_type_single_node | ccc_type_single_node_s3 | ccc_type_multi_node_quick | ccc_type_multi_node_durable
# variable "type" {
#   default = "ccc_type_multi_node_quick"
# }

variable "worker_type" {
  default = "t2.micro"
}

variable "region" {
  description = "AWS region"
  default = "us-east-1"
}

variable "public_key" {
  description = "TODO:"
  default = ""
}

variable "bucket_name" {
  default = "ccc-job-storage-"
}


