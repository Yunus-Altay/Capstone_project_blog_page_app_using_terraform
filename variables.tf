variable "vpc_cidr_block" {
  default     = "90.90.0.0/16"
  description = "Default VPC cidr block"
}

variable "vpc_tag_name" {
  default = "simaox-capstone-vpc"
}

# variable "public_subnet_a_cidr" {
#   default     = "90.90.10.0/24"
#   description = "Default public subnet-a cidr block"
# }

# variable "public_subnet_b_cidr" {
#   default     = "90.90.20.0/24"
#   description = "Default public subnet-b cidr block"
# }

# variable "private_subnet_a_cidr" {
#   default     = "90.90.11.0/24"
#   description = "Default private subnet-a cidr block"
# }

# variable "private_subnet_b_cidr" {
#   default     = "90.90.21.0/24"
#   description = "Default prviate subnet-b cidr block"
# }

variable "subnet_name_tag" {
  default     = "aws_simaox"
  description = "Default VPC cidr block"
}

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

variable "s3_bucket_1" {
  default = "simaox-capstone-content-bucket"

}