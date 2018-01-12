variable "access_key" {}
variable "secret_key" {}
variable "public_key" {}
variable "region" {}

#CCC stack in AWS
module "ccc" {
  source      = "git::https://github.com/dionjwa/cloud-compute-cannon//etc/terraform/aws/modules/stack_cheapest_scalable?ref=master"
  # source      = "../../modules/stack_cheapest_scalable"
  access_key  = "${var.access_key}"
  secret_key  = "${var.secret_key}"
  region      = "${var.region}"
  public_key  = "${var.public_key}"
}

output "kibana" {
  value = "http://${module.ccc.kibana}:5601"
}

output "url" {
  value = "http://${module.ccc.url}"
}