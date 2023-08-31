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

resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "${var.tag_name}_db_subnet_group"
  description = "Subnets available for the RDS DB Instance"
  subnet_ids = [
    aws_subnet.private_subnet[0].id,
    aws_subnet.private_subnet[1].id,
  ]
  tags = {
    Name = "${var.tag_name}_db_subnet_group"
  }
}

resource "aws_db_instance" "default" {
  allocated_storage           = 20
  allow_major_version_upgrade = false
  backup_retention_period     = 0
  db_name                     = var.db_name
  db_subnet_group_name        = aws_db_subnet_group.db_subnet_group.name 
  delete_automated_backups = true
  engine                   = "mysql"
  engine_version           = "8.0.28"
  instance_class           = "db.t2.micro"
  identifier = "${lower(var.tag_name)}-db-instance"
  username                 = var.db_username
  password                 = var.db_password
  maintenance_window       = "Mon:03:00-Mon:04:00"
  max_allocated_storage    = 30
  multi_az                 = false
  port                     = 3306
  # publicly_accessible = true
  skip_final_snapshot    = true
  # storage_encrypted      = true
  vpc_security_group_ids = [aws_security_group.rds_sec_gr.id] 
  tags = {
    Name = "${var.tag_name}_db_instance"
  }
}