# -----------------------------------------------------------------------------------------
# Image Builder Pipeline Module Variables
# -----------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------------------

variable "pipeline_name" {
  description = "Name of the image pipeline"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.pipeline_name))
    error_message = "Pipeline name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "pipeline_description" {
  description = "Description of the image pipeline"
  type        = string
  default     = null
}

variable "pipeline_status" {
  description = "Status of the pipeline (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.pipeline_status)
    error_message = "Pipeline status must be either ENABLED or DISABLED."
  }
}

variable "aws_region" {
  description = "AWS region for pipeline operations"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------------------
# Infrastructure Configuration
# -----------------------------------------------------------------------------------------

variable "infrastructure_description" {
  description = "Description for infrastructure configuration"
  type        = string
  default     = null
}

variable "instance_profile_name" {
  description = "IAM instance profile name for Image Builder instances"
  type        = string
}

variable "instance_types" {
  description = "List of EC2 instance types to use for building"
  type        = list(string)
  default     = ["m5.large"]
}

variable "security_group_ids" {
  description = "List of security group IDs for the build instance"
  type        = list(string)
}

variable "subnet_id" {
  description = "Subnet ID for the build instance"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 key pair name for SSH access to build instances"
  type        = string
  default     = null
}

variable "terminate_instance_on_failure" {
  description = "Whether to terminate the instance on build failure"
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for build notifications"
  type        = string
  default     = null
}

variable "enable_imdsv2" {
  description = "Enable IMDSv2 for enhanced security"
  type        = bool
  default     = true
}

variable "resource_tags" {
  description = "Tags to apply to resources created during the build"
  type        = map(string)
  default     = {}
}

variable "s3_logging_bucket" {
  description = "S3 bucket name for Image Builder logs"
  type        = string
  default     = null
}

variable "s3_logging_prefix" {
  description = "S3 key prefix for logs"
  type        = string
  default     = "logs"
}

# -----------------------------------------------------------------------------------------
# Image Recipe Configuration
# -----------------------------------------------------------------------------------------

variable "recipe_description" {
  description = "Description for the image recipe"
  type        = string
  default     = null
}

variable "parent_image" {
  description = "Parent image ARN or SSM parameter for base image"
  type        = string
}

variable "recipe_version" {
  description = "Version of the recipe (semver format)"
  type        = string
  default     = "1.0.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.recipe_version))
    error_message = "Recipe version must be in semantic versioning format (e.g., 1.0.0)."
  }
}

variable "block_device_mappings" {
  description = "Block device mappings for the AMI"
  type = list(object({
    device_name  = string
    no_device    = optional(bool)
    virtual_name = optional(string)
    ebs = optional(object({
      delete_on_termination = optional(bool, true)
      encrypted             = optional(bool, true)
      iops                  = optional(number)
      kms_key_id            = optional(string)
      snapshot_id           = optional(string)
      throughput            = optional(number)
      volume_size           = optional(number, 20)
      volume_type           = optional(string, "gp3")
    }))
  }))
  default = [
    {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 20
        volume_type           = "gp3"
        delete_on_termination = true
        encrypted             = true
      }
    }
  ]
}

variable "aws_components" {
  description = "List of AWS-managed component ARNs with optional parameters"
  type = list(object({
    arn        = string
    parameters = optional(map(string), {})
  }))
  default = []
}

variable "custom_component_arns" {
  description = "List of custom component ARNs with optional parameters"
  type = list(object({
    arn        = string
    parameters = optional(map(string), {})
  }))
  default = []
}

variable "uninstall_ssm_agent_after_build" {
  description = "Whether to uninstall SSM agent after the build"
  type        = bool
  default     = false
}

variable "user_data_base64" {
  description = "Base64-encoded user data for customization"
  type        = string
  default     = null
}

variable "working_directory" {
  description = "Working directory for component execution"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------------------
# Distribution Configuration
# -----------------------------------------------------------------------------------------

variable "enable_distribution" {
  description = "Whether to enable AMI distribution"
  type        = bool
  default     = true
}

variable "distribution_description" {
  description = "Description for distribution configuration"
  type        = string
  default     = null
}

variable "distribution_regions" {
  description = "List of regions and their distribution configurations"
  type = list(object({
    region              = string
    ami_name_pattern    = string
    ami_description     = optional(string)
    ami_tags            = optional(map(string), {})
    kms_key_id          = optional(string)
    target_account_ids  = optional(list(string))
    
    launch_permission = optional(object({
      organization_arns        = optional(list(string))
      organizational_unit_arns = optional(list(string))
      user_groups              = optional(list(string))
      user_ids                 = optional(list(string))
    }))
    
    # Container distribution
    container_repository_name = optional(string)
    container_service         = optional(string, "ECR")
    container_tags            = optional(list(string), [])
    container_description     = optional(string)
    
    # Launch template configurations
    launch_template_configurations = optional(list(object({
      launch_template_id = optional(string)
      account_id         = optional(string)
      default            = optional(bool, false)
    })), [])
    
    # License configurations
    license_configuration_arns = optional(list(string))
  }))
  default = []
}

# -----------------------------------------------------------------------------------------
# Pipeline Schedule Configuration
# -----------------------------------------------------------------------------------------

variable "schedule_expression" {
  description = "Cron or rate expression for pipeline schedule"
  type        = string
  default     = null

  validation {
    condition = var.schedule_expression == null || (
      can(regex("^(cron|rate)\\(.*\\)$", var.schedule_expression))
    )
    error_message = "Schedule expression must be in cron(...) or rate(...) format."
  }
}

variable "pipeline_execution_start_condition" {
  description = "Condition for starting pipeline execution"
  type        = string
  default     = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"

  validation {
    condition = contains([
      "EXPRESSION_MATCH_ONLY",
      "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"
    ], var.pipeline_execution_start_condition)
    error_message = "Invalid pipeline execution start condition."
  }
}

variable "schedule_timezone" {
  description = "Timezone for the schedule (e.g., UTC, America/New_York)"
  type        = string
  default     = "UTC"
}

# -----------------------------------------------------------------------------------------
# Image Testing Configuration
# -----------------------------------------------------------------------------------------

variable "image_tests_enabled" {
  description = "Whether to enable image tests"
  type        = bool
  default     = true
}

variable "image_tests_timeout_minutes" {
  description = "Timeout for image tests in minutes"
  type        = number
  default     = 60

  validation {
    condition     = var.image_tests_timeout_minutes >= 60 && var.image_tests_timeout_minutes <= 1440
    error_message = "Image tests timeout must be between 60 and 1440 minutes."
  }
}

# -----------------------------------------------------------------------------------------
# Enhanced Features
# -----------------------------------------------------------------------------------------

variable "enhanced_image_metadata_enabled" {
  description = "Whether to enable enhanced image metadata collection"
  type        = bool
  default     = true
}

variable "enable_image_scanning" {
  description = "Whether to enable image scanning"
  type        = bool
  default     = false
}

variable "ecr_repository_name" {
  description = "ECR repository name for container scanning"
  type        = string
  default     = null
}

variable "ecr_container_tags" {
  description = "Container tags for ECR scanning"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------------------
# Execution Options
# -----------------------------------------------------------------------------------------

variable "trigger_pipeline_on_create" {
  description = "Whether to trigger pipeline execution on creation"
  type        = bool
  default     = false
}