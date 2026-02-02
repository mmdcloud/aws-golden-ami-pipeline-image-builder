# Variables
variable "primary_region" {
  description = "Primary AWS region for AMI creation"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for Image Builder instances"
  type        = string
}

variable "notification_email" {
  type    = string
}

variable "key_pair_name" {
  description = "Key pair name for EC2 instances"
  type        = string
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
}