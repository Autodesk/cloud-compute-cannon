resource "aws_iam_role" "terraform_ccc_lambda_role" {
  name = "terraform_ccc_lambda_role"
  path = "/"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": ["lambda.amazonaws.com"]
      },
      "Action": ["sts:AssumeRole"]
    }
  ]
}
EOF
}

resource "aws_iam_policy" "terraform_ccc_lambda_iam_scale_policy" {
  name_prefix = "terraform_ccc_lambda_iam_scale_policy"
  path = "/"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["logs:*"],
      "Resource": ["arn:aws:logs:*:*:*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:TerminateInstances",
        "ec2:DescribeNetworkInterfaces",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "autoscaling:*"
      ],
      "Resource": ["*"]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "terraform_ccc_lambda_policy_attachment" {
  policy_arn = "${aws_iam_policy.terraform_ccc_lambda_iam_scale_policy.arn}"
  role = "${aws_iam_role.terraform_ccc_lambda_role.name}"
}

resource "aws_cloudwatch_event_rule" "terraform_ccc_lambda_scale_timer_rule" {
  name        = "terraform_ccc_lambda-rule-scale-timer"
  description = "Fire this event every minute"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "terraform_ccc_lambda_scale_timer_target" {
    rule = "${aws_cloudwatch_event_rule.terraform_ccc_lambda_scale_timer_rule.name}"
    target_id = "terraform_ccc_lambda_scale"
    arn = "${aws_lambda_function.terraform_ccc_lambda_scale.arn}"
}

resource "aws_lambda_permission" "terraform_ccc_allow_cloudwatch_to_call_lambda_scale" {
  statement_id   = "PermissionInvokeLambdaScale"
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.terraform_ccc_lambda_scale.function_name}"
  principal      = "events.amazonaws.com"
  source_arn     = "${aws_cloudwatch_event_rule.terraform_ccc_lambda_scale_timer_rule.arn}"
}

resource "aws_lambda_function" "terraform_ccc_lambda_scale" {
  filename         = "${path.module}/lambda.zip"
  function_name    = "terraform_ccc_lambda_scale"
  role             = "${aws_iam_role.terraform_ccc_lambda_role.arn}"
  handler          = "index.handlerScale"
  runtime          = "nodejs6.10"
  timeout          = 60
  vpc_config {
    subnet_ids = ["${var.subnet_ids}"]
    security_group_ids = ["${var.security_group_ids}"]
  }

  environment {
    variables {
      REDIS_HOST = "${var.redis_host}"
      ASG_NAME = "${var.asg_name}"
    }
  }

  source_code_hash = "${base64sha256(file("${path.module}/lambda.zip"))}"
}