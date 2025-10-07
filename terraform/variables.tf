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