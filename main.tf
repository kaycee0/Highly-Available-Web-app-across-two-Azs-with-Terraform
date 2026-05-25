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
