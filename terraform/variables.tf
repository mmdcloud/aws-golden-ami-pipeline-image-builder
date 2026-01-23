# Variables
variable "primary_region" {
  description = "Primary AWS region for AMI creation"
  type        = string
  default     = "us-east-1"
}

variable "subnet_id" {
  description = "Subnet ID for Image Builder instances"
  type        = string
  default     = "us-east-1a"
}

variable "notification_email" {
  type    = string
  default = "madmaxcloudonline@gmail.com"
}

variable "key_pair_name" {
  description = "Key pair name for EC2 instances"
  type        = string
  default     = "madmaxkeypair"
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}