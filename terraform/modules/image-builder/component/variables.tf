# -----------------------------------------------------------------------------------------
# Image Builder Component Module Variables
# -----------------------------------------------------------------------------------------

variable "component_name" {
  description = "Name of the Image Builder component"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.component_name))
    error_message = "Component name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "description" {
  description = "Description of the component"
  type        = string
  default     = null
}

variable "platform" {
  description = "Platform for the component (Linux or Windows)"
  type        = string

  validation {
    condition     = contains(["Linux", "Windows"], var.platform)
    error_message = "Platform must be either 'Linux' or 'Windows'."
  }
}

variable "version" {
  description = "Version of the component (semver format)"
  type        = string
  default     = "1.0.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.version))
    error_message = "Version must be in semantic versioning format (e.g., 1.0.0)."
  }
}

variable "component_data" {
  description = "Raw YAML component data. If null, will use template file"
  type        = string
  default     = null
}

variable "component_template_path" {
  description = "Path to the component template file"
  type        = string
  default     = ""
}

variable "component_template_vars" {
  description = "Variables to pass to the component template"
  type        = map(string)
  default     = {}
}

variable "supported_os_versions" {
  description = "List of supported OS versions for this component"
  type        = list(string)
  default     = null
}

variable "kms_key_id" {
  description = "KMS key ID for encrypting component data"
  type        = string
  default     = null
}

variable "change_description" {
  description = "Description of changes in this version"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags for the component"
  type        = map(string)
  default     = {}
}