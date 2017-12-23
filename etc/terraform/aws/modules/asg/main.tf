resource "aws_autoscaling_group" "asg_worker" {
  # availability_zones        = ["${var.availability_zones}"]
  vpc_zone_identifier       = ["${var.subnets}"]
  name_prefix               = "ccc-asg-worker-"
  max_size                  = "${var.max_size}"
  min_size                  = "${var.min_size}"
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = "${aws_launch_configuration.worker.name}"
  load_balancers            = ["${aws_elb.worker_elb.name}"]

  timeouts {
    delete = "15m"
  }

  tag {
    key                 = "Name"
    value               = "CCCWorker"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "worker" {
  name_prefix   = "terraform-ccc-worker-lc-"
  image_id      = "${lookup(var.amis, var.region)}"
  instance_type = "t2.micro"
  security_groups = ["${aws_security_group.server.id}", "${var.redis_security_group_id}"]
  user_data =  <<EOF
#!/bin/bash
docker run --detach \
 --restart always \
 --publish "9000:9000" \
 -v "/var/run/docker.sock:/var/run/docker.sock" \
 -e REDIS_HOST=${var.redis_host} \
 -e FLUENT_HOST=${var.fluent_host} \
 -e FLUENT_PORT=${var.fluent_port} \
 -e LOG_LEVEL=${var.log_level} \
  dionjwa/cloud-compute-cannon:${var.version}
EOF

  lifecycle {
    create_before_destroy = true
  }

  key_name = "${var.key_name}"

  # depends_on = ["aws_elasticache_cluster.default", "aws_internet_gateway.main"]
}


resource "aws_security_group" "server" {
  description = "server/worker sg"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port        = 9000
    to_port          = 9000
    protocol         = "tcp"
    #Swap these two if you need to hit a specific machine
    # cidr_blocks      = ["0.0.0.0/0"]
    security_groups  = ["${aws_security_group.worker_elb.id}"]
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

resource "aws_elb" "worker_elb" {
  name               = "ccc-terraform-elb"
  security_groups    = ["${aws_security_group.worker_elb.id}", "${aws_security_group.server.id}"]
  subnets            = ["${var.subnets}"]

  listener {
    instance_port     = 9000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  # listener {
  #   instance_port      = 9000
  #   instance_protocol  = "http"
  #   lb_port            = 443
  #   lb_protocol        = "https"
  #   ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/certName"
  # }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    target              = "HTTP:9000/test"
    interval            = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags {
    Name = "ccc-terraform-elb"
  }
}

resource "aws_security_group" "worker_elb" {
  description = "worker_elb sg"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}
