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
  name = "${var.tag_name}-lambda-role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        # Sid    = "",
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

resource "aws_alb" "app_lb" {
  name               = "${var.tag_name}-lb-tf"
  ip_address_type    = "ipv4"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sec_gr.id]
  subnets            = [
    aws_subnet.public_subnet[0].id,
    aws_subnet.public_subnet[1].id,
  ]
  tags = {
    Name = "${var.tag_name}-lb-tf"
  }
}

resource "aws_alb_target_group" "app_lb_tg" {
  name        = "${var.tag_name}-lb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main_vpc.id
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = {
    Name = "${var.tag_name}-lb-tf"
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
}

resource "aws_alb_listener" "app_listener_http" {
  load_balancer_arn = aws_alb.app_lb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
      # host = "#{host}"
      # path = "/#{path}"
      # query = "#{query}"
  }
  tags = {
    Name = "${var.tag_name}-listener-http"
  }
}

resource "aws_alb_listener" "app_listener_https" {
  load_balancer_arn = aws_alb.app_lb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn = aws_acm_certificate.certificate.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.app_lb_tg.arn
  }
  tags = {
    Name = "${var.tag_name}-listener-https"
  }
}

# "${join("", ["*.", split(".", var.domain_name)[1], ".", split(".", var.domain_name)[2]])}"

# resource "aws_route53_zone" "r53_zone" {
#   name = var.root_domain_name
# }

data "aws_route53_zone" "selected" {
  name         = var.existing_hosted_zone
  private_zone = false
}

resource "aws_acm_certificate" "certificate" {
  domain_name       = var.root_domain_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_dns" {
  allow_overwrite = true
  name            = tolist(aws_acm_certificate.certificate.domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.certificate.domain_validation_options)[0].resource_record_value]
  type            = tolist(aws_acm_certificate.certificate.domain_validation_options)[0].resource_record_type
  zone_id         = data.aws_route53_zone.selected.zone_id
  ttl             = 60
}

resource "aws_acm_certificate_validation" "hello_cert_validate" {
  certificate_arn         = aws_acm_certificate.certificate.arn
  validation_record_fqdns = [aws_route53_record.cert_dns.fqdn]
}

resource "aws_iam_role" "lt_role" {
  name               = "${var.tag_name}-lt-role"
  path               = "/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        # Sid    = "",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ]
}

resource "aws_iam_instance_profile" "lt_role_profile" {
  name = "${var.tag_name}-lt-role-profile"
  role = aws_iam_role.role.name
  path = "/"
}

resource "aws_launch_template" "asg_lt" {
  name                   = "${var.tag_name}-lt"
  image_id               = data.aws_ami.al2023.id
  iam_instance_profile = {
    name = "${var.tag_name}-lt-role-profile"
  }
  instance_type          = "t2.micro"
  key_name               = var.key-name
  vpc_security_group_ids = [aws_security_group.ec2_sec_gr.id]
  user_data              = base64encode(templatefile("user-data.sh", { user-data-git-token = var.git-token, user-data-git-name = var.git-name })) # ??
  depends_on             = [github_repository_file.dbendpoint]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.tag_name}-lt"
    }
  }
}

resource "aws_autoscaling_group" "app_asg" {
  default_cooldown = 200
  max_size                  = 4
  min_size                  = 1
  desired_capacity          = 2
  name                      = "${var.tag_name}-lt-asg"
  health_check_grace_period = 300
  health_check_type         = "ELB"
  target_group_arns         = [aws_alb_target_group.app_lb_tg.arn]
  vpc_zone_identifier       = [
    aws_subnet.private_subnet[0].id,
    aws_subnet.private_subnet[1].id,
  ]
  launch_template {
    id      = aws_launch_template.asg_lt.id
    version = aws_launch_template.asg_lt.latest_version
  }
  tags = {
    Name = "${var.tag_name}-lt-asg"
  }
}

resource "aws_autoscaling_policy" "asg_policy" {
  autoscaling_group_name = aws_autoscaling_group.app_asg.group_names
  name                   = "${var.tag_name}-asg-policy"
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

resource "aws_autoscaling_notification" "asg_notifications" {
  group_names = [
    aws_autoscaling_group.app_asg.name
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.sns_topic.arn 
}

resource "aws_sns_topic" "sns_topic" {
  name = "server-status-change"
}

resource "aws_sns_topic_subscription" "EmailSubscription" {
  topic_arn = aws_sns_topic.sns_topic.arn
  protocol  = "email"
  endpoint  = var.operator_email 
}


    