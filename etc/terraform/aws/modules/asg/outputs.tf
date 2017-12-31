output "name" {
  value = "${aws_autoscaling_group.terraform_ccc_asg_worker.name}"
}

output "url" {
  value = "${aws_elb.terraform_ccc_worker_elb.dns_name }"
}