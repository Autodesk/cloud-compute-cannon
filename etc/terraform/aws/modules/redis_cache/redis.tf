#Create the redis instance
resource "aws_elasticache_cluster" "default" {
  cluster_id           = "redis-ccc"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  port                 = 6379
  subnet_group_name    = "${aws_elasticache_subnet_group.default.name}"
  security_group_ids   = ["{aws_security_group.redis.id}"]
  parameter_group_name = "ccc.redis"
}

resource "aws_elasticache_subnet_group" "default" {
  name       = "ccc-redis-subnet"
  subnet_ids = ["${aws_subnet.subnet1.id}", "${aws_subnet.subnet2.id}"]
}