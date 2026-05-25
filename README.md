# Highly-Available-Web-app-across-two-Azs-with-Terraform
A fleet of EC2 instances running a web application, highly available across two AZs, sits behind a load balancer, and scale automatically based on CPU usage


For the Private Subnet

cidrsubnet(var.vpc_cidr, 8, count.index + length(var.azs))

var.vpc_cidr — base CIDR, e.g. "10.0.0.0/16"
8 — adds 8 bits to the prefix, so /16 + 8 = /24
count.index + length(var.azs) — this is the key part

The offset explained:
If var.azs = ["us-east-1a", "us-east-1b"] then length(var.azs) = 2

Subnet	    Count.index 	Count.index+length(var.azs) 	CIDR
Private-0	0	             0+2	                       10.0.2.0/24
Private-1	1	             0+1	                       10.0.3.0/24