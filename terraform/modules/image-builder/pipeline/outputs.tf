# -----------------------------------------------------------------------------------------
# Image Builder Pipeline Module Outputs
# -----------------------------------------------------------------------------------------

output "pipeline_arn" {
  description = "ARN of the Image Builder pipeline"
  value       = aws_imagebuilder_image_pipeline.this.arn
}

output "pipeline_name" {
  description = "Name of the pipeline"
  value       = aws_imagebuilder_image_pipeline.this.name
}

output "pipeline_id" {
  description = "ID of the pipeline"
  value       = aws_imagebuilder_image_pipeline.this.id
}

output "infrastructure_configuration_arn" {
  description = "ARN of the infrastructure configuration"
  value       = aws_imagebuilder_infrastructure_configuration.this.arn
}

output "image_recipe_arn" {
  description = "ARN of the image recipe"
  value       = aws_imagebuilder_image_recipe.this.arn
}

output "image_recipe_name" {
  description = "Name of the image recipe"
  value       = aws_imagebuilder_image_recipe.this.name
}

output "distribution_configuration_arn" {
  description = "ARN of the distribution configuration"
  value       = var.enable_distribution ? aws_imagebuilder_distribution_configuration.this[0].arn : null
}

output "distribution_regions" {
  description = "List of regions where AMI will be distributed"
  value       = [for region in var.distribution_regions : region.region]
}

output "schedule_expression" {
  description = "Schedule expression for the pipeline"
  value       = var.schedule_expression
}