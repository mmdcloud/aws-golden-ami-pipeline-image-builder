# -----------------------------------------------------------------------------------------
# Image Builder Component Module
# Creates custom Image Builder components for AMI customization
# -----------------------------------------------------------------------------------------

resource "aws_imagebuilder_component" "this" {
  name        = var.component_name
  description = var.description
  platform    = var.platform
  version     = var.version
  
  data = var.component_data != null ? var.component_data : templatefile(
    var.component_template_path,
    var.component_template_vars
  )
   
  supported_os_versions = var.supported_os_versions

  # KMS encryption for component data (if provided)
  kms_key_id = var.kms_key_id

  # Change description for versioning
  change_description = var.change_description

  tags = merge(
    var.tags,
    {
      Name      = var.component_name
      Version   = var.version
      Platform  = var.platform
      ManagedBy = "terraform"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}