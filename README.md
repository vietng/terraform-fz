## Terraform project to provision FamilyZone environment

### AMI
AMI is based on Ubuntu 20.04 LTS.

### Stack
* Create using Terraform
* Java app: http://fz-app.hecatus.com/
  * Run on a number of EC2 on-demand instances (t3.small) behind a ALB with round robin balancing algorithm.
  * Instances are created from a launch configuration and resides in an auto scaling group.
  * ALB performs health checks on port 8080.
* Grafana app: http://fz-grafana.hecatus.com
  * Similar to the Java app stack with the exception of health check port being 3000.
### Architecture diagram (to be updated)
