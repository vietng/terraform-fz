variable "aws_config" {
  type = map
  default = {
    profile = "default"
    region  = "ap-southeast-1"
  }
}

variable "name_prefix" {
  description = <<DESCRIPTION
Name prefix to make resource names unique when supported
DESCRIPTION
}

variable "stack_config" {
  type = map
  default = {
    vpc_cidr         = "10.1.0.0/16"
    vpc_name         = "FZ VPC"
    dns_zone_id      = "Z01853903SGNMEAO1UAOV"
    app_lb_cname     = "app-fz-test"     # in dns_zone context
    grafana_lb_cname = "grafana-fz-test" # in dns_zone context

    # If you change the cidr, make sure to review `/.env` as well
    fz_sn_1_cidr = "10.1.1.0/24"
    fz_sn_1_name = "FZ Subnet 1"

    fz_sn_2_cidr = "10.1.2.0/24"
    fz_sn_2_name = "FZ Subnet 2"

    public_cidr = "0.0.0.0/0"

    app_as_health_grace     = 90 #in seconds
    app_as_default_cooldown = 90 #in seconds

    app_lc_ami           = "ami-08804995da1223690"
    app_lc_instance_type = "t3.small"
    app_lc_vol_size      = 10 #in gb
    app_lc_key_name      = "amristarkey"
  }
}
