# Variables
variable "primary_region" {
  description = "Primary AWS region for AMI creation"
  type        = string
}

variable "notification_email" {
  type        = string
  description = "Email address to receive AMI pipeline and security notifications"
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
variable "project" {
  description = "Project Name"
  type        = string
}