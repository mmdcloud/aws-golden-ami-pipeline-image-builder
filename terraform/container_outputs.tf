# --------------------------------------------------------------------------------
# Container Recipe & Pipeline Outputs
# --------------------------------------------------------------------------------

output "container_recipe_arn" {
  description = "ARN of the EC2 Image Builder container recipe"
  value       = var.enable_container_recipe ? aws_imagebuilder_container_recipe.golden_container[0].arn : null
}

output "container_ecr_repository_url" {
  description = "URL of the Amazon ECR repository storing golden container images"
  value       = var.enable_container_recipe ? aws_ecr_repository.golden_container[0].repository_url : null
}

output "container_ecr_repository_arn" {
  description = "ARN of the Amazon ECR repository storing golden container images"
  value       = var.enable_container_recipe ? aws_ecr_repository.golden_container[0].arn : null
}

output "container_pipeline_arn" {
  description = "ARN of the EC2 Image Builder container pipeline"
  value       = var.enable_container_recipe && var.enable_container_pipeline ? aws_imagebuilder_image_pipeline.golden_container[0].arn : null
}

output "container_hardening_component_arn" {
  description = "ARN of the container security hardening component"
  value       = var.enable_container_recipe ? aws_imagebuilder_component.container_security_hardening[0].arn : null
}
