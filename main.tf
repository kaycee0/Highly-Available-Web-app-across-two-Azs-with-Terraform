## AWS VPC

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
    tags = {
        Name = "${var.project_name}-vpc"
    }
}
### Internet Gateway

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}

### Elastic IPs for NAT Gateways

resource "aws_eip" "nat_1" {
  domain = "vpc"
  tags = {
    Name = "${var.project_name}-eip-nat-1"
  }
}

resource "aws_eip" "nat_2" {
  domain = "vpc"
  tags = {
    Name = "${var.project_name}-eip-nat-2"
  }
}

### Subnets

# Public subnets — host the ALB and NAT Gateways
resource "aws_subnet" "public" {
 count = length(var.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = var.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index}-${var.project_name}"
  }
}

# Private subnets — host the EC2 instances (no direct internet exposure)
resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = var.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + length(var.azs))
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-${count.index}-${var.project_name}"
  }
}

# NAT Gateway allows private subnet instances to reach the internet (e.g. for package installs)
# without being directly reachable from the internet.
resource "aws_nat_gateway" "nat_1" {
  allocation_id = aws_eip.nat_1.id
  subnet_id     = aws_subnet.public[0].id  # NAT Gateways must live in a PUBLIC subnet

  depends_on = [aws_internet_gateway.igw]
  tags = {
    Name = "${var.project_name}-nat-gateway-1"
  }
}

resource "aws_nat_gateway" "nat_2" {
  allocation_id = aws_eip.nat_2.id
  subnet_id     = aws_subnet.public[1].id

  depends_on = [aws_internet_gateway.igw]
  tags = {
    Name = "${var.project_name}-nat-gateway-2"
  }
}

### Route Tables

# Public route table — directs internet-bound traffic to the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Private route tables — direct internet-bound traffic to the NAT Gateway
resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1.id
  }
  tags = {
    Name = "${var.project_name}-private-rt-1"
  }
}

resource "aws_route_table" "private_2" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_2.id
  }
  tags = {
    Name = "${var.project_name}-private-rt-2"
  }
}

### Route Table Associations

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public[1].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private[0].id
  route_table_id = aws_route_table.private_1.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private[1].id
  route_table_id = aws_route_table.private_2.id
}

### EC2 AMI Image

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

### IAM Role, Policy Attachment, and Instance Profile

resource "aws_iam_role" "app" {
  name = "RedBullRacing-Ec2-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "RedBullRacing-Ec2-instance-profile"
  role = aws_iam_role.app.name
}

### Security Groups

# ALB security group — accepts HTTP from the internet
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP inbound from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# App security group — only accepts traffic from the ALB, not the open internet
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow traffic only from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}