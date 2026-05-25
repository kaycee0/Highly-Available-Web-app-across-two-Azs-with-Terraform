## AWS VPC

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}
### Internet Gateway

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

### Elastic IP and NAT Gateway
# NAT Gateway allows private subnet instances to reach the internet (e.g. for package installs)
# without being directly reachable from the internet.

resource "aws_eip" "nat_1" {
  domain = "vpc"
  tags = {
    Name = "eip for Nat Gateway1"
  }
}

resource "aws_eip" "nat_2" {
  domain = "vpc"
  tags = {
    Name = "eip for Nat Gateway2"
  }
}