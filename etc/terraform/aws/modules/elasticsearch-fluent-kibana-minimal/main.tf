
resource "aws_instance" "elasticsearch-stack-mini" {
  ami = "${lookup(var.amis, var.region)}"
  instance_type = "${var.instance_type}"
  subnet_id = "${var.subnet_id}"
  vpc_security_group_ids = ["${aws_security_group.fluent.id}"]
  monitoring  = true
  associate_public_ip_address = true

  # Examine /var/log/cloud-init-output.log for errors
  user_data = "${file("${path.module}/init-fluent-instance.sh")}"

  key_name = "${var.key_name}"

  tags {
    Name = "fluent"
  }

  root_block_device {
      volume_size = "10"
  }
}

resource "aws_security_group" "fluent" {
  description = "fluent sg"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port        = 8888
    to_port          = 8888
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    from_port        = 24224
    to_port          = 24224
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    from_port        = 9200
    to_port          = 9200
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    from_port        = 9300
    to_port          = 9300
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    from_port        = 5601
    to_port          = 5601
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 65535
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}
