output "name" {
  value = "${aws_autoscaling_group.asg_worker.name}"
}

output "url" {
  value = "${aws_elb.worker_elb.dns_name }"
}