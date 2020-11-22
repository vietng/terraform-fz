provider "aws" {
  profile = var.aws_config.profile
  region  = var.aws_config.region
}


resource "aws_vpc" "default" {
  cidr_block           = var.stack_config.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = join(":", [var.name_prefix, var.stack_config.vpc_name])
  }
}


# Create an internet gateway to give our subnets access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}


# Grant the VPC internet access on its main route table
resource "aws_route" "internet-access" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}

# Available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# 2 subnets for hosting instances
resource "aws_subnet" "fz-sn-1" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = var.stack_config.fz_sn_1_cidr
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    Name = join(":", [var.name_prefix, var.stack_config.fz_sn_1_name])
  }
}

resource "aws_subnet" "fz-sn-2" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = var.stack_config.fz_sn_2_cidr
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[1]
  tags = {
    Name = join(":", [var.name_prefix, var.stack_config.fz_sn_2_name])
  }
}

# Associate subnets to route table explicitly
# Without explicit associations, the subbets will still be associated with the VPC main route table. 
resource "aws_route_table_association" "rt-s-1" {
  subnet_id      = aws_subnet.fz-sn-1.id
  route_table_id = aws_vpc.default.main_route_table_id
}

resource "aws_route_table_association" "rt-s-2" {
  subnet_id      = aws_subnet.fz-sn-2.id
  route_table_id = aws_vpc.default.main_route_table_id
}


resource "aws_cloudwatch_metric_alarm" "app-unhealthy-alarm" {
  alarm_name          = join("-", [var.name_prefix, "app-unhealthy-alarm"])
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = [aws_sns_topic.app-unhealthy-topic.arn]

  # Aggregate metric using the load balancer as dimension
  namespace = "AWS/ApplicationELB"
  dimensions = {
    LoadBalancer = replace(aws_lb.app-fz-lb.arn, "/(.*loadbalancer\\/)(app.*)/", "$2")
    TargetGroup  = replace(aws_lb_target_group.fz-app-target-group.arn, "/(.*)(targetgroup.*)/", "$2")
  }
  evaluation_periods = 1
  period             = 60
  metric_name        = "UnHealthyHostCount"
  statistic          = "Average"
  threshold          = 1

}

resource aws_sns_topic "app-unhealthy-topic" {
  name = join("-", [var.name_prefix, "app-unhealthy-topic"])
}

resource "aws_cloudwatch_metric_alarm" "grafana-unhealthy-alarm" {
  alarm_name          = join("-", [var.name_prefix, "grafana-unhealthy-alarm"])
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = [aws_sns_topic.grafana-unhealthy-topic.arn]

  # Aggregate metric using the load balancer as dimension
  namespace = "AWS/ApplicationELB"
  dimensions = {
    LoadBalancer = replace(aws_lb.grafana-fz-lb.arn, "/(.*loadbalancer\\/)(app.*)/", "$2")
    TargetGroup  = replace(aws_lb_target_group.fz-grafana-target-group.arn, "/(.*)(targetgroup.*)/", "$2")
  }
  evaluation_periods = 1
  period             = 60
  metric_name        = "UnHealthyHostCount"
  statistic          = "Average"
  threshold          = 1

}

resource aws_sns_topic "grafana-unhealthy-topic" {
  name = join("-", [var.name_prefix, "grafana-unhealthy-topic"])
}

#########################################################################################
# Grafana stack
#########################################################################################
# Grafana Load Balancer to distribute traffic for 2 subnets
# - A aws_lb resource of type "application"
# - Listener to target group
# - Target group whincludes healthcheck definition
resource "aws_lb" "grafana-fz-lb" {
  name                             = join("-", [var.name_prefix, "grafana-fz-lb"])
  load_balancer_type               = "application"
  internal                         = false
  enable_cross_zone_load_balancing = true
  enable_http2                     = true
  security_groups                  = [aws_security_group.grafana-lb-sc.id]

  subnet_mapping {
    subnet_id = aws_subnet.fz-sn-1.id
  }
  subnet_mapping {
    subnet_id = aws_subnet.fz-sn-2.id
  }
}

# Security group for Grafana LB
resource "aws_security_group" "grafana-lb-sc" {
  name   = join("-", [var.name_prefix, "grafana-lb-sc"])
  vpc_id = aws_vpc.default.id

  ingress {
    description = "Connection from internet on port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = [var.stack_config.public_cidr]
  }
}

# Egress rules for grafana-lb-sc
# Health check rule - Allow load balancer nodes to perform health checks on app instances
resource "aws_security_group_rule" "grafana-healthcheck" {
  type                     = "egress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "TCP"
  security_group_id        = aws_security_group.grafana-lb-sc.id
  source_security_group_id = aws_security_group.fz-app-instance-sc.id
}

# Listener for the Grafana stack
resource "aws_lb_listener" "grafana-listener" {
  load_balancer_arn = aws_lb.grafana-fz-lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fz-grafana-target-group.arn
  }
}

# Grafana Target group.
# Use "instance" type so that the group can be used with Auto Scaling.
resource "aws_lb_target_group" "fz-grafana-target-group" {
  name                          = join("-", [var.name_prefix, "fz-grafana-target-group"])
  target_type                   = "instance"
  port                          = 3000
  protocol                      = "HTTP"
  vpc_id                        = aws_vpc.default.id
  deregistration_delay          = 30
  load_balancing_algorithm_type = "round_robin"
  slow_start                    = 30

  # Healthcheck using HTTP:3000
  health_check {
    path                = "/login"
    enabled             = true
    port                = 3000
    protocol            = "HTTP"
    interval            = 20
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 18
    matcher             = "200"
  }
}

# Security group for Grafana instance
# - HTTP health check from ALB
# - SSH from anywhere
# - Communuication from/to grafana instances
# - Connection from load balancing nodes
resource "aws_security_group" "fz-grafana-instance-sc" {
  name   = join("-", [var.name_prefix, "fz-grafana-instance-sc"])
  vpc_id = aws_vpc.default.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "TCP"
    security_groups = [aws_security_group.grafana-lb-sc.id]
    description     = "Connection from LB"
  }
}


#########################################################################################
# Java Application stack
#########################################################################################
# App Load Balancer to distribute traffic for 2 subnets
# - A aws_lb resource of type "application"
# - Listener to target group
# - Target group whincludes healthcheck definition
resource "aws_lb" "app-fz-lb" {
  name                             = join("-", [var.name_prefix, "app-fz-lb"])
  load_balancer_type               = "application"
  internal                         = false
  enable_cross_zone_load_balancing = true
  enable_http2                     = true
  security_groups                  = [aws_security_group.app-lb-sc.id]

  subnet_mapping {
    subnet_id = aws_subnet.fz-sn-1.id
  }
  subnet_mapping {
    subnet_id = aws_subnet.fz-sn-2.id
  }
}

# Java App
# Security group for App LB
resource "aws_security_group" "app-lb-sc" {
  name   = join("-", [var.name_prefix, "app-lb-sc"])
  vpc_id = aws_vpc.default.id

  ingress {
    description = "Connection from internet on port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = [var.stack_config.public_cidr]
  }
}

# Egress rules for app-lb-sc
# Health check rule - Allow load balancer nodes to perform health checks on app instances
resource "aws_security_group_rule" "app-healthcheck" {
  type                     = "egress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "TCP"
  security_group_id        = aws_security_group.app-lb-sc.id
  source_security_group_id = aws_security_group.fz-app-instance-sc.id
}

# Listener for the Java app stack
resource "aws_lb_listener" "java-application-listener" {
  load_balancer_arn = aws_lb.app-fz-lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fz-app-target-group.arn
  }
}


# App Target group.
# Use "instance" type so that the group can be used with Auto Scaling.
resource "aws_lb_target_group" "fz-app-target-group" {
  name                          = join("-", [var.name_prefix, "fz-app-target-group"])
  target_type                   = "instance"
  port                          = 8080
  protocol                      = "HTTP"
  vpc_id                        = aws_vpc.default.id
  deregistration_delay          = 30
  load_balancing_algorithm_type = "round_robin"
  slow_start                    = 30

  # Healthcheck using HTTP:8080
  health_check {
    path                = "/"
    enabled             = true
    port                = 8080
    protocol            = "HTTP"
    interval            = 20
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 18
    matcher             = "200"
  }
}


# Security group for App instance
# - HTTP health check from ALB
# - SSH from anywhere
# - Communuication from/to grafana instances
# - Connection from load balancing nodes
resource "aws_security_group" "fz-app-instance-sc" {
  name   = join("-", [var.name_prefix, "fz-app-instance-sc"])
  vpc_id = aws_vpc.default.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "TCP"
    security_groups = [aws_security_group.app-lb-sc.id]
    description     = "Connection from LB and grafana instances"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = [var.stack_config.public_cidr]
    description = "SSH from permited CIDR"
  }

  # Allow access to the Internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# App Auto Scaling group
# use "name_prefix" to guarantee name uniqueness so that "create_before_destroy" works
resource "aws_autoscaling_group" "app-as" {
  name_prefix           = join("-", [var.name_prefix, "app-as"])
  max_size              = 1
  min_size              = 1
  desired_capacity      = 1
  health_check_type     = "ELB"
  protect_from_scale_in = false

  # Associate the as group with the NLB target group
  target_group_arns = [aws_lb_target_group.fz-app-target-group.arn, aws_lb_target_group.fz-grafana-target-group.arn]

  # Launch config
  launch_configuration = aws_launch_configuration.app-lc.name
  vpc_zone_identifier  = [aws_subnet.fz-sn-1.id, aws_subnet.fz-sn-2.id]

  # periods
  default_cooldown          = var.stack_config.app_as_default_cooldown
  health_check_grace_period = var.stack_config.app_as_health_grace

  lifecycle {
    create_before_destroy = true
  }
}

# App Launch config
# use "name_prefix" to guarantee name uniqueness so that "create_before_destroy" works
resource "aws_launch_configuration" "app-lc" {
  name_prefix                 = join("-", [var.name_prefix, "app-lc"])
  image_id                    = var.stack_config.app_lc_ami
  instance_type               = var.stack_config.app_lc_instance_type
  associate_public_ip_address = true
  enable_monitoring           = false # detailed monitoring
  ebs_optimized               = false

  # IAM and key
  key_name = var.stack_config.app_lc_key_name

  security_groups = [aws_security_group.fz-app-instance-sc.id, aws_security_group.fz-grafana-instance-sc.id]

  root_block_device {
    volume_size           = var.stack_config.app_lc_vol_size
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
  }

  user_data = file("./scripts/cloud-init.sh")
}


# DNS update
data "aws_route53_zone" "zone" {
  zone_id = var.stack_config.dns_zone_id
}

resource "aws_route53_zone_association" "vpc-dns-zone-association" {
  zone_id = data.aws_route53_zone.zone.zone_id
  vpc_id  = aws_vpc.default.id
}

resource "aws_route53_record" "app-lb-cname" {
  zone_id         = data.aws_route53_zone.zone.zone_id
  name            = var.stack_config.app_lb_cname
  ttl             = 300
  type            = "CNAME"
  records         = [aws_lb.app-fz-lb.dns_name]
  allow_overwrite = true
}

resource "aws_route53_record" "grafana-lb-cname" {
  zone_id         = data.aws_route53_zone.zone.zone_id
  name            = var.stack_config.grafana_lb_cname
  ttl             = 300
  type            = "CNAME"
  records         = [aws_lb.grafana-fz-lb.dns_name]
  allow_overwrite = true
}


# Outputs
output "APP_LB_DNS_NAME" {
  value       = aws_lb.app-fz-lb.dns_name
  description = "DNS of the APP load balancer."
}
output "GRAFANA_LB_DNS_NAME" {
  value       = aws_lb.grafana-fz-lb.dns_name
  description = "DNS of the Grafana load balancer."
}
