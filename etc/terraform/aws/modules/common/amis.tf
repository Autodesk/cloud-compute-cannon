# ECS optimized AWS linux, with docker installed.
# The stack logic is all in docker images, so no other pieces are needed.
# http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html
variable "amis" {
  type = "map"
  default = {
    us-east-2 = "ami-b0527dd5"
    us-east-1 = "ami-20ff515a"
    us-west-2 = "ami-3702ca4f"
    us-west-1 = "ami-b388b4d3"
    eu-west-1 = "ami-d65dfbaf"
    eu-west-2 = "ami-ee7d618a"
    eu-central-1 = "ami-ebfb7e84"
    ap-northeast-2 = "ami-70d0741e"
    ap-northeast-1 = "ami-95903df3"
    ap-southeast-2 = "ami-e3b75981"
    ap-southeast-1 = "ami-c8c98bab"
    ca-central-1 = "ami-fc5fe798"
  }
}