# -----------------------------------------------------------------------------------------
# Image Builder Pipeline Module
# Creates complete Image Builder pipeline with recipe, infrastructure, distribution
# -----------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------
# Infrastructure Configuration
# -----------------------------------------------------------------------------------------
resource "aws_imagebuilder_infrastructure_configuration" "this" {
  name                          = "${var.pipeline_name}-infra"
  description                   = var.infrastructure_description
  instance_profile_name         = var.instance_profile_name
  instance_types                = var.instance_types
  security_group_ids            = var.security_group_ids
  subnet_id                     = var.subnet_id
  terminate_instance_on_failure = var.terminate_instance_on_failure
  key_pair                      = var.key_pair_name

  # SNS Topic for notifications
  sns_topic_arn = var.sns_topic_arn

  # Instance metadata options
  dynamic "instance_metadata_options" {
    for_each = var.enable_imdsv2 ? [1] : []
    content {
      http_tokens                 = "required"
      http_put_response_hop_limit = 1
    }
  }

  # Logging configuration
  dynamic "logging" {
    for_each = var.s3_logging_bucket != null ? [1] : []
    content {
      s3_logs {
        s3_bucket_name = var.s3_logging_bucket
        s3_key_prefix  = var.s3_logging_prefix
      }
    }
  }

  # Resource tags for instances
  resource_tags = var.resource_tags

  tags = merge(
    var.tags,
    {
      Name      = "${var.pipeline_name}-infra"
      ManagedBy = "terraform"
    }
  )
}

# -----------------------------------------------------------------------------------------
# Image Recipe
# -----------------------------------------------------------------------------------------
resource "aws_imagebuilder_image_recipe" "this" {
  name         = "${var.pipeline_name}-recipe"
  description  = var.recipe_description
  parent_image = var.parent_image
  version      = var.recipe_version

  # Block device mappings
  dynamic "block_device_mapping" {
    for_each = var.block_device_mappings
    content {
      device_name  = block_device_mapping.value.device_name
      no_device    = lookup(block_device_mapping.value, "no_device", null)
      virtual_name = lookup(block_device_mapping.value, "virtual_name", null)

      dynamic "ebs" {
        for_each = lookup(block_device_mapping.value, "ebs", null) != null ? [block_device_mapping.value.ebs] : []
        content {
          delete_on_termination = lookup(ebs.value, "delete_on_termination", true)
          encrypted             = lookup(ebs.value, "encrypted", true)
          iops                  = lookup(ebs.value, "iops", null)
          kms_key_id            = lookup(ebs.value, "kms_key_id", null)
          snapshot_id           = lookup(ebs.value, "snapshot_id", null)
          throughput            = lookup(ebs.value, "throughput", null)
          volume_size           = lookup(ebs.value, "volume_size", 20)
          volume_type           = lookup(ebs.value, "volume_type", "gp3")
        }
      }
    }
  }

  # AWS-managed components
  dynamic "component" {
    for_each = var.aws_components
    content {
      component_arn = component.value.arn
      
      dynamic "parameter" {
        for_each = lookup(component.value, "parameters", {})
        content {
          name  = parameter.key
          value = parameter.value
        }
      }
    }
  }

  # Custom components
  dynamic "component" {
    for_each = var.custom_component_arns
    content {
      component_arn = component.value.arn

      dynamic "parameter" {
        for_each = lookup(component.value, "parameters", {})
        content {
          name  = parameter.key
          value = parameter.value
        }
      }
    }
  }

  # Systems Manager Agent
  dynamic "systems_manager_agent" {
    for_each = var.uninstall_ssm_agent_after_build ? [1] : []
    content {
      uninstall_after_build = true
    }
  }

  # User data for customization
  user_data_base64 = var.user_data_base64

  # Working directory
  working_directory = var.working_directory

  tags = merge(
    var.tags,
    {
      Name      = "${var.pipeline_name}-recipe"
      Version   = var.recipe_version
      ManagedBy = "terraform"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------------------
# Distribution Configuration
# -----------------------------------------------------------------------------------------
resource "aws_imagebuilder_distribution_configuration" "this" {
  count = var.enable_distribution ? 1 : 0

  name        = "${var.pipeline_name}-distribution"
  description = var.distribution_description

  # Distribution per region
  dynamic "distribution" {
    for_each = var.distribution_regions
    content {
      region = distribution.value.region

      ami_distribution_configuration {
        name        = distribution.value.ami_name_pattern
        description = distribution.value.ami_description

        ami_tags = merge(
          var.tags,
          lookup(distribution.value, "ami_tags", {}),
          {
            SourceAMI   = "{{ imagebuilder:sourceImage }}"
            BuildDate   = "{{ imagebuilder:buildDate }}"
            RecipeName  = "{{ imagebuilder:recipeName }}"
            PipelineName = var.pipeline_name
          }
        )

        # KMS encryption
        kms_key_id = lookup(distribution.value, "kms_key_id", null)

        # Launch permissions
        dynamic "launch_permission" {
          for_each = lookup(distribution.value, "launch_permission", null) != null ? [distribution.value.launch_permission] : []
          content {
            organization_arns        = lookup(launch_permission.value, "organization_arns", null)
            organizational_unit_arns = lookup(launch_permission.value, "organizational_unit_arns", null)
            user_groups              = lookup(launch_permission.value, "user_groups", null)
            user_ids                 = lookup(launch_permission.value, "user_ids", null)
          }
        }

        # Target account IDs for sharing
        target_account_ids = lookup(distribution.value, "target_account_ids", null)
      }

      # Container distribution (if enabled)
      dynamic "container_distribution_configuration" {
        for_each = lookup(distribution.value, "container_repository_name", null) != null ? [1] : []
        content {
          container_tags = lookup(distribution.value, "container_tags", [])
          description    = lookup(distribution.value, "container_description", null)

          target_repository {
            repository_name = distribution.value.container_repository_name
            service         = lookup(distribution.value, "container_service", "ECR")
          }
        }
      }

      # Launch template configurations
      dynamic "launch_template_configuration" {
        for_each = lookup(distribution.value, "launch_template_configurations", [])
        content {
          launch_template_id = lookup(launch_template_configuration.value, "launch_template_id", null)
          account_id         = lookup(launch_template_configuration.value, "account_id", null)
          default            = lookup(launch_template_configuration.value, "default", false)
        }
      }

      # License configurations
      license_configuration_arns = lookup(distribution.value, "license_configuration_arns", null)
    }
  }

  tags = merge(
    var.tags,
    {
      Name      = "${var.pipeline_name}-distribution"
      ManagedBy = "terraform"
    }
  )
}

# -----------------------------------------------------------------------------------------
# Image Pipeline
# -----------------------------------------------------------------------------------------
resource "aws_imagebuilder_image_pipeline" "this" {
  name        = var.pipeline_name
  description = var.pipeline_description
  status      = var.pipeline_status

  image_recipe_arn                 = aws_imagebuilder_image_recipe.this.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.this.arn
  distribution_configuration_arn   = var.enable_distribution ? aws_imagebuilder_distribution_configuration.this[0].arn : null

  # Schedule
  dynamic "schedule" {
    for_each = var.schedule_expression != null ? [1] : []
    content {
      schedule_expression                = var.schedule_expression
      pipeline_execution_start_condition = var.pipeline_execution_start_condition
      timezone                           = var.schedule_timezone
    }
  }

  # Enhanced metadata
  enhanced_image_metadata_enabled = var.enhanced_image_metadata_enabled

  # Image scanning
  dynamic "image_scanning_configuration" {
    for_each = var.enable_image_scanning ? [1] : []
    content {
      image_scanning_enabled = true

      dynamic "ecr_configuration" {
        for_each = var.ecr_repository_name != null ? [1] : []
        content {
          repository_name = var.ecr_repository_name
          container_tags  = var.ecr_container_tags
        }
      }
    }
  }

  # Image tests configuration
  image_tests_configuration {
    image_tests_enabled = var.image_tests_enabled
    timeout_minutes     = var.image_tests_timeout_minutes
  }

  tags = merge(
    var.tags,
    {
      Name      = var.pipeline_name
      ManagedBy = "terraform"
    }
  )

  depends_on = [
    aws_imagebuilder_infrastructure_configuration.this,
    aws_imagebuilder_image_recipe.this
  ]
}

# -----------------------------------------------------------------------------------------
# Optional: Trigger pipeline execution on creation
# -----------------------------------------------------------------------------------------
resource "null_resource" "trigger_pipeline" {
  count = var.trigger_pipeline_on_create ? 1 : 0

  triggers = {
    pipeline_arn = aws_imagebuilder_image_pipeline.this.arn
  }

  provisioner "local-exec" {
    command = "aws imagebuilder start-image-pipeline-execution --image-pipeline-arn ${aws_imagebuilder_image_pipeline.this.arn} --region ${var.aws_region}"
  }

  depends_on = [aws_imagebuilder_image_pipeline.this]
}