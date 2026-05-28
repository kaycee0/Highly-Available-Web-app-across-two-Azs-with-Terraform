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

# AWS Infrastructure — Terraform

A production-grade AWS infrastructure definition using Terraform, deploying a highly available, auto-scaling web application behind an Application Load Balancer across multiple Availability Zones.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Infrastructure Components](#infrastructure-components)
  - [VPC & Networking](#vpc--networking)
  - [Security Groups](#security-groups)
  - [IAM](#iam)
  - [Compute (EC2 / Launch Template)](#compute-ec2--launch-template)
  - [Load Balancer](#load-balancer)
  - [Auto Scaling](#auto-scaling)
- [Prerequisites](#prerequisites)
- [Variables](#variables)
- [Usage](#usage)
- [Traffic Flow](#traffic-flow)
- [Security Considerations](#security-considerations)
- [Cost Considerations](#cost-considerations)
- [Known Limitations & Gotchas](#known-limitations--gotchas)

---

## Architecture Overview

```
                          ┌─────────────────────────────────────────────────────────┐
                          │                        AWS VPC                          │
                          │                                                         │
  Internet                │  ┌──────────────────────────────────────────────────┐  │
     │                    │  │               Public Subnets (x2 AZs)            │  │
     │  HTTP :80          │  │                                                  │  │
     ▼                    │  │   ┌─────────────────┐   ┌─────────────────────┐  │  │
┌─────────┐               │  │   │  NAT Gateway 1  │   │   NAT Gateway 2     │  │  │
│  Users  │──────────────▶│  │   │  (EIP)          │   │   (EIP)             │  │  │
└─────────┘               │  │   └─────────────────┘   └─────────────────────┘  │  │
                          │  │                                                  │  │
                          │  │   ┌──────────────────────────────────────────┐  │  │
                          │  │   │     Application Load Balancer (ALB)      │  │  │
                          │  │   │     (internet-facing, port 80)           │  │  │
                          │  │   └──────────────────┬───────────────────────┘  │  │
                          │  └─────────────────────-│──────────────────────────┘  │
                          │                         │ forward :8080               │
                          │  ┌──────────────────────▼───────────────────────────┐ │
                          │  │              Private Subnets (x2 AZs)            │ │
                          │  │                                                  │ │
                          │  │  ┌────────────────┐     ┌────────────────────┐  │ │
                          │  │  │  EC2 Instance  │     │   EC2 Instance     │  │ │
                          │  │  │  (AZ 1)        │     │   (AZ 2)           │  │ │
                          │  │  │  port 8080     │ ... │   port 8080        │  │ │
                          │  │  └────────────────┘     └────────────────────┘  │ │
                          │  │         Auto Scaling Group (min: 2, max: 5)     │ │
                          │  └──────────────────────────────────────────────────┘ │
                          └─────────────────────────────────────────────────────────┘
```

**Key design principles:**

- **High Availability**: Resources spread across 2 Availability Zones.
- **Private Compute**: EC2 instances live in private subnets with no public IPs, unreachable directly from the internet.
- **Controlled Egress**: Outbound internet access from private subnets is routed through NAT Gateways (one per AZ for AZ-resiliency).
- **Least-Privilege Networking**: The app security group only accepts traffic from the ALB security group, not the open internet.
- **Elastic Scaling**: An Auto Scaling Group adjusts capacity based on CPU utilisation, keeping average utilisation near 60%.

---

## Infrastructure Components

### VPC & Networking

| Resource | Name | Description |
|---|---|---|
| `aws_vpc` | `{project_name}-vpc` | Top-level network boundary for all resources |
| `aws_internet_gateway` | `{project_name}-igw` | Enables the VPC to communicate with the internet |
| `aws_subnet` (public x2) | `public-subnet-{n}-{project_name}` | Hosts the ALB and NAT Gateways; instances get public IPs |
| `aws_subnet` (private x2) | `private-subnet-{n}-{project_name}` | Hosts EC2 instances; no public IP assignment |
| `aws_eip` (x2) | `{project_name}-eip-nat-{n}` | Static public IPs attached to each NAT Gateway |
| `aws_nat_gateway` (x2) | `{project_name}-nat-gateway-{n}` | One per AZ; allows private instances to reach the internet |
| `aws_route_table` (public) | `{project_name}-public-rt` | Routes `0.0.0.0/0` → Internet Gateway |
| `aws_route_table` (private x2) | `{project_name}-private-rt-{n}` | Routes `0.0.0.0/0` → NAT Gateway (per-AZ) |
| `aws_route_table_association` (x4) | — | Binds each subnet to its route table |

**Subnet CIDR allocation** uses `cidrsubnet(var.vpc_cidr, 8, index)`:
- Public subnets: index `0`, `1` (e.g. `10.0.0.0/24`, `10.0.1.0/24`)
- Private subnets: index `2`, `3` (e.g. `10.0.2.0/24`, `10.0.3.0/24`) — offset by `length(var.azs)`

---

### Security Groups

#### ALB Security Group (`{project_name}-alb-sg`)

| Direction | Protocol | Port | Source |
|---|---|---|---|
| Inbound | TCP | 80 | `0.0.0.0/0` (open internet) |
| Outbound | All | All | `0.0.0.0/0` |

The ALB is the single public entry point. All HTTP traffic enters here.

#### App Security Group (`{project_name}-app-sg`)

| Direction | Protocol | Port | Source |
|---|---|---|---|
| Inbound | TCP | 8080 | ALB Security Group only |
| Outbound | All | All | `0.0.0.0/0` |

EC2 instances are not reachable from the internet — only from the ALB. This enforces traffic must pass through the load balancer.

---

### IAM

| Resource | Name | Purpose |
|---|---|---|
| `aws_iam_role` | `RedBullRacing-Ec2-Role` | EC2 assume-role trust policy |
| `aws_iam_role_policy_attachment` | — | Attaches `AmazonSSMManagedInstanceCore` |
| `aws_iam_instance_profile` | `RedBullRacing-Ec2-instance-profile` | Binds the IAM role to EC2 instances |

The `AmazonSSMManagedInstanceCore` policy allows instances to be managed via **AWS Systems Manager Session Manager** — enabling shell access without needing SSH keys or open port 22. This is the recommended zero-trust approach to instance access.

---

### Compute (EC2 / Launch Template)

| Setting | Value |
|---|---|
| AMI | Latest `al2023-ami-*-x86_64` (Amazon Linux 2023, dynamically resolved) |
| Instance Type | `t2.micro` |
| Launch Template Name | `RedBullRacing-launch-template` |
| Public IP | Disabled (private subnet only) |
| Security Group | App SG |
| IAM Profile | `RedBullRacing-Ec2-instance-profile` |

The AMI is resolved dynamically using a `data` source, so the ASG always launches the most recent Amazon Linux 2023 image without manual updates.

> **Note**: `t2.micro` is suitable for development/testing. For production workloads, consider `t3.small` or larger, and review burstable instance CPU credit behaviour under sustained load.

---

### Load Balancer

| Resource | Setting | Value |
|---|---|---|
| ALB | Scheme | Internet-facing |
| ALB | Subnets | Public subnet AZ-1 and AZ-2 |
| ALB | Deletion Protection | **Enabled** |
| Target Group | Port | 8080 |
| Target Group | Protocol | HTTP |
| Listener | Port | 80 |
| Listener | Action | Forward → Target Group |

Traffic enters the ALB on port 80 and is forwarded to registered EC2 instances on port 8080.

> **Production recommendation**: Add an HTTPS listener (port 443) with an ACM certificate and redirect HTTP → HTTPS. Never serve production traffic over unencrypted HTTP.

---

### Auto Scaling

| Setting | Value |
|---|---|
| Min Capacity | 2 |
| Max Capacity | 5 |
| Desired Capacity | 4 |
| Health Check Type | `ELB` (uses ALB health checks) |
| Health Check Grace Period | 300 seconds |
| Scaling Policy | Target Tracking — `ASGAverageCPUUtilization` |
| Target CPU | 60% |

The ASG uses ELB health checks, meaning an instance is only considered healthy if the ALB reports it as healthy (not just EC2 status checks). Instances are spread across both private subnets / AZs.

The CPU target tracking policy automatically adds or removes instances to maintain average CPU at 60%.

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) `>= 1.3.0`
- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials (`aws configure` or environment variables)
- An AWS account with permissions to create VPCs, EC2, IAM roles, ALBs, and Auto Scaling resources
- An AWS region with at least **2 Availability Zones** (all standard regions qualify)

---

## Variables

| Variable | Type | Description | Example |
|---|---|---|---|
| `vpc_cidr` | `string` | CIDR block for the VPC | `"10.0.0.0/16"` |
| `project_name` | `string` | Prefix used for all resource names and tags | `"RedBullRacing"` |
| `azs` | `list(string)` | List of AZs to deploy into (must be ≥ 2) | `["eu-west-1a", "eu-west-1b"]` |

Example `terraform.tfvars`:

```hcl
vpc_cidr     = "10.0.0.0/16"
project_name = "RedBullRacing"
azs          = ["eu-west-1a", "eu-west-1b"]
```

---

## Usage

```bash
# 1. Initialise — downloads provider plugins
terraform init

# 2. Review the execution plan
terraform plan -var-file="terraform.tfvars"

# 3. Apply the configuration
terraform apply -var-file="terraform.tfvars"

# 4. Destroy all resources when done
terraform destroy -var-file="terraform.tfvars"
```

> **Warning**: `enable_deletion_protection = true` is set on the ALB. You must disable this in the AWS Console (or via Terraform) before `terraform destroy` will succeed.

---

## Traffic Flow

```
User HTTP request
  → Internet Gateway
    → ALB (public subnet, port 80)
      → Target Group (port 8080)
        → EC2 Instance (private subnet, port 8080)

EC2 outbound (e.g. package installs, API calls)
  → Private route table
    → NAT Gateway (public subnet, EIP)
      → Internet Gateway
        → Internet
```

---

## Security Considerations

| Area | Current State | Recommendation |
|---|---|---|
| Transport Encryption | HTTP only (port 80) | Add ACM certificate + HTTPS listener; redirect HTTP → HTTPS |
| SSH Access | No SSH keys configured | Use SSM Session Manager (already enabled via IAM) |
| Instance Exposure | Private subnets, no public IPs ✅ | — |
| ALB Exposure | Internet-facing on port 80 | Restrict by IP range if not a public service |
| Deletion Protection | Enabled on ALB ✅ | Also enable on critical resources in state |
| Secrets Management | Not configured | Use AWS Secrets Manager or SSM Parameter Store for app secrets |
| WAF | Not configured | Consider AWS WAF on the ALB for production workloads |
| VPC Flow Logs | Not configured | Enable for audit/debugging |
| IMDSv2 | Not enforced in launch template | Add `metadata_options { http_tokens = "required" }` |

---

## Cost Considerations

The following resources incur ongoing charges (approximate, `eu-west-1`):

| Resource | Approx. Cost |
|---|---|
| NAT Gateway (x2) | ~$0.048/hr each + data transfer |
| ALB | ~$0.022/hr + LCU charges |
| EC2 `t2.micro` (x4 desired) | ~$0.0116/hr each |
| Elastic IPs (unattached) | $0.005/hr if unattached — these are always attached here |

NAT Gateways are typically the largest cost driver. For non-production environments, consider using a single NAT Gateway (or a NAT instance) to reduce costs.

---

## Known Limitations & Gotchas

- **`force_delete = true` on ASG**: Instances will be terminated immediately on destroy without waiting for connections to drain. Set to `false` in production.
- **`t2.micro` CPU credits**: Under sustained CPU load, `t2.micro` instances exhaust CPU credits and throttle. Use `t3` instances for predictable performance.
- **No HTTPS**: The listener is HTTP-only. Do not deploy sensitive applications without adding TLS.
- **No ALB access logs**: Consider enabling S3 access logging on the ALB for audit trails.
- **AMI filter is broad**: `al2023-ami-*-x86_64` may match multiple AMIs; `most_recent = true` picks the latest. Pin to a specific AMI ID for fully reproducible builds.
- **Hardcoded IAM role names**: `RedBullRacing-Ec2-Role` and `RedBullRacing-Ec2-instance-profile` are hardcoded rather than derived from `var.project_name`. Deploying multiple stacks in the same account will cause naming conflicts.
- **No remote state**: For team use, configure an S3 backend with DynamoDB state locking.