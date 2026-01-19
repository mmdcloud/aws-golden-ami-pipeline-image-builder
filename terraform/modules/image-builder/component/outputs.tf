# -----------------------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------------------

output "arn" {
  description = "ARN of the Image Builder component"
  value       = aws_imagebuilder_component.this.arn
}

output "name" {
  description = "Name of the component"
  value       = aws_imagebuilder_component.this.name
}

output "version" {
  description = "Version of the component"
  value       = aws_imagebuilder_component.this.version
}

output "type" {
  description = "Type of the component"
  value       = aws_imagebuilder_component.this.type
}