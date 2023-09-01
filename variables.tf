variable "vpc_cidr_block" {
  default     = "90.90.0.0/16"
  description = "Default VPC cidr block"
}

variable "tag_name" {
  default = "simaox-capstone"
}

# variable "subnet_name_tag" {
#   default     = "aws_simaox"
#   description = "Default VPC cidr block"
# }

variable "subnet_cidrs_public" {
  description = "Subnet CIDRs for public subnets (length must match configured availability_zones)"
  default     = ["90.90.10.0/24", "90.90.20.0/24"]
  type        = list(string)
}

variable "subnet_cidrs_private" {
  description = "Subnet CIDRs for private subnets (length must match configured availability_zones)"
  default     = ["90.90.11.0/24", "90.90.21.0/24"]
  type        = list(string)
}

variable "availability_zones" {
  description = "AZs in this region to use"
  default     = ["us-east-1a", "us-east-1b"]
  type        = list(string)
}

variable "s3_bucket_content" {
  default = "simaox-capstone-s3-bucket-content"
}

variable "rds_db_name" {
  default = "database1"
}
variable "db_username" {
  default = "admin"
}

variable "db_password" {
  default = "admin1234"
}
