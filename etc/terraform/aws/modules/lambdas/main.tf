resource "aws_iam_role" "ccc_lambda_role" {
  name = "ccc_lambda_role"
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

resource "aws_iam_policy" "lambda_iam_scale_policy" {
  name_prefix = "lambda_iam_scale_policy"
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

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  policy_arn = "${aws_iam_policy.lambda_iam_scale_policy.arn}"
  role = "${aws_iam_role.ccc_lambda_role.name}"
}

resource "aws_cloudwatch_event_rule" "lambda_scale_up_timer_rule" {
  name        = "lambda-rule-scale-up-timer"
  description = "Fire this event every minute"
  schedule_expression = "rate(1 minute)"
  # role_arn = "${aws_lambda_function.lambda_scale_up.arn}"
}

resource "aws_cloudwatch_event_target" "lambda_scale_up_timer_target" {
    rule = "${aws_cloudwatch_event_rule.lambda_scale_up_timer_rule.name}"
    target_id = "lambda_scale_up"
    arn = "${aws_lambda_function.lambda_scale_up.arn}"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda_scale_up" {
  statement_id   = "PermissionInvokeLambdaScaleUp"
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.lambda_scale_up.function_name}"
  principal      = "events.amazonaws.com"
  source_arn     = "${aws_cloudwatch_event_rule.lambda_scale_up_timer_rule.arn}"
}

resource "aws_lambda_function" "lambda_scale_up" {
  filename         = "${var.lambda_zip_file}"
  function_name    = "scaling_up_lambda"
  role             = "${aws_iam_role.ccc_lambda_role.arn}"
  handler          = "index.handlerScaleUp"
  runtime          = "nodejs6.10"
  timeout          = 30
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

  source_code_hash = "${base64sha256(file("${var.lambda_zip_file}"))}"
}