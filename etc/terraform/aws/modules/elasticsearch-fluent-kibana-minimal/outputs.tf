output "hostname" {
  value = "${aws_instance.elasticsearch-stack-mini.public_ip}"
}
