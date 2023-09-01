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

resource "aws_db_instance" "db_instance" {
  allocated_storage           = 20
  allow_major_version_upgrade = false
  backup_retention_period     = 0
  db_name                     = var.rds_db_name
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

resource "aws_s3_bucket" "s3_bucket_content" {
  bucket = var.s3_bucket_content

  tags = {
    Name        = "${var.tag_name}-s3-bucket-content"
  }
}

resource "aws_s3_bucket_ownership_controls" "bucket_content_ownership" {
  bucket = aws_s3_bucket.s3_bucket_content.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "bucket_content_public_access_block" {
  bucket = aws_s3_bucket.s3_bucket_content.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "bucket_content_acl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.bucket_content_ownership,
    aws_s3_bucket_public_access_block.bucket_content_public_access_block,
  ]

  bucket = aws_s3_bucket.s3_bucket_content.id
  acl    = "public-read"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_dynamodb_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "media/"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

data "aws_caller_identity" "current" {}
output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

locals {
    account_id = data.aws_caller_identity.current.account_id
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_dynamodb_function.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.s3_bucket_content.arn
  source_account = local.account_id
}

resource "local_file" "config" {
  content  = templatefile("${path.module}/lambda.py", { dynamo-db-name = ""}) # dynamo-db-name
  filename = "${path.module}/lambda.py"
}

data "archive_file" "lambdazip" {
  type        = "zip"
  output_path = "lambda_function_payload.zip"
  source_file = "${path.module}/lambda.py"

  depends_on = [
    local_file.config,
  ]
}

resource "aws_lambda_function" "lambda_dynamodb_function" {
  description = "S3-dynamoDB lambda function"
  filename      = "lambda_function_payload.zip"
  function_name = "S3DynamoLambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.8"

  depends_on = [
    aws_dynamodb_table.my_dynamo_db,
    archive_file.lambdazip
    ]
}

resource "aws_iam_role" "lambda_role" {
  name = "test_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Sid    = "",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  path = "/"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/job-function/NetworkAdministrator"
  ]

  inline_policy {
    name = "dynamodb"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action   = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem"
          ],
          Effect   = "Allow",
          Resource = "arn:aws:dynamodb:*:*:*"
        },
      ]
    })
  }

  inline_policy {
    name = "s3"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action   = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:GetObjectVersion"
          ],
          Effect   = "Allow",
          Resource = "*"
        },
        {
          Action   = ["lambda:Invoke*"],
          Effect   = "Allow",
          Resource = "*"
        }
      ]
    })
  }

  tags = {
    tag-key = "tag-value"
  }
}