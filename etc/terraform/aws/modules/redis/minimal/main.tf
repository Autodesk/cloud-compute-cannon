
resource "aws_instance" "terraform_ccc_redis" {
  ami = "${lookup(var.amis, var.region)}"
  instance_type = "${var.instance_type}"
  subnet_id = "${var.subnet_id}"
  vpc_security_group_ids = ["${aws_security_group.terraform_ccc_redis.id}"]
  monitoring  = true
  associate_public_ip_address = true

  # Examine /var/log/cloud-init-output.log for errors
  user_data = "${file("${path.module}/init-redis-instance.sh")}"

  key_name = "${var.key_name}"

  tags {
    Name = "terraform-ccc-redis-micro"
  }
}

resource "aws_security_group" "terraform_ccc_redis" {
  description = "Restrict redis access to servers and workers"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port         = 6379
    to_port           = 6379
    protocol          = "tcp"
    cidr_blocks       = ["0.0.0.0/0"]
  }

  egress {
    from_port         = 6379
    to_port           = 6379
    protocol          = "tcp"
    cidr_blocks       = ["0.0.0.0/0"]
  }

  ingress {
    from_port         = 22
    to_port           = 22
    protocol          = "tcp"
    cidr_blocks       = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
