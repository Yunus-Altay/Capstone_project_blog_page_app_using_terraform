terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_cidr_block
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  tags = {
    Name = "${var.vpc_tag_name}"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "aws_capstone_igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.subnet_cidrs_public)

  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.subnet_cidrs_public[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "${var.subnet_name_tag}-public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.subnet_cidrs_private)

  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.subnet_cidrs_private[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "${var.subnet_name_tag}-private-subnet-${count.index}"
  }
}


resource "aws_route_table" "main_public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = var.vpc_cidr_block
    gateway_id = "local"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }
  tags = {
    Name = "simaox-capstone-public-rt"
  }
}

resource "aws_route_table_association" "rt_associate_public" {
  count          = length(var.subnet_cidrs_public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.main_public_rt.id
}

resource "aws_route_table" "main_private_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = var.vpc_cidr_block
    gateway_id = "local"
  }
  tags = {
    Name = "simaox-capstone-private-rt"
  }
}

resource "aws_route_table_association" "rt_associate_private" {
  count          = length(var.subnet_cidrs_private)
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = aws_route_table.main_private_rt.id
}

resource "aws_vpc_endpoint" "vpc_endpoint_s3" {
  vpc_id            = aws_vpc.main_vpc.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  depends_on = [aws_s3_bucket.s3_bucket_content]
  tags = {
    Name = "S3-vpc-endpoint-for-content-bucket"
  }
}

resource "aws_vpc_endpoint_route_table_association" "rt_associate_s3_endpoint" {
  route_table_id  = aws_route_table.main_private_rt.id
  vpc_endpoint_id = aws_vpc_endpoint.vpc_endpoint_s3.id
}

resource "aws_s3_bucket" "s3_bucket_content" {
  bucket = var.s3_bucket_1
}