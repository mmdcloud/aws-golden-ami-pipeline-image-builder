# Outputs
output "image_pipeline_arn" {
  value = aws_imagebuilder_image_pipeline.golden_ami.arn
}

output "sns_topic_arn" {
  value = module.ami_events_sns.topic_arn
}