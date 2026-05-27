variable "primary_region" {
  description = "Primary AWS region for AMI creation and the Image Builder pipeline."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.primary_region))
    error_message = "primary_region must be a valid AWS region identifier (e.g. us-east-1, eu-west-2)."
  }
}

variable "notification_email" {
  description = "Email address to receive AMI pipeline build results, Inspector findings, and Security Hub critical alerts."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.notification_email))
    error_message = "notification_email must be a valid email address."
  }
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks for the Image Builder VPC. Must have one entry per AZ listed in var.azs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnets) >= 1 && length(var.public_subnets) == length(var.azs)
    error_message = "public_subnets must contain exactly one CIDR per availability zone in var.azs."
  }

  validation {
    condition     = alltrue([for cidr in var.public_subnets : can(cidrhost(cidr, 0))])
    error_message = "All entries in public_subnets must be valid CIDR blocks (e.g. 10.0.1.0/24)."
  }
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks for the Image Builder VPC. Must have one entry per AZ listed in var.azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnets) >= 1 && length(var.private_subnets) == length(var.azs)
    error_message = "private_subnets must contain exactly one CIDR per availability zone in var.azs."
  }

  validation {
    condition     = alltrue([for cidr in var.private_subnets : can(cidrhost(cidr, 0))])
    error_message = "All entries in private_subnets must be valid CIDR blocks (e.g. 10.0.4.0/24)."
  }
}

variable "azs" {
  description = "List of AWS Availability Zones for the Image Builder VPC. Must all belong to var.primary_region."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two availability zones are required for high-availability NAT gateway placement."
  }
}

variable "project" {
  description = "Project name. Used as a tag value on all resources and as the AMI tag selector in the Config approved-AMIs rule."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,27}$", var.project))
    error_message = "project must be 2–28 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}