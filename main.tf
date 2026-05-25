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