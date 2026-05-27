# ── Pipeline ─────────────────────────────────────────────────────────────────

output "image_pipeline_arn" {
  description = "ARN of the EC2 Image Builder pipeline. Use this to trigger manual builds via the console or CLI: aws imagebuilder start-image-pipeline-execution --image-pipeline-arn <value>"
  value       = aws_imagebuilder_image_pipeline.golden_ami.arn
}

output "image_recipe_arn" {
  description = "ARN of the base Linux image recipe (version-locked). Reference this when creating additional pipelines that should share the same hardened base."
  value       = aws_imagebuilder_image_recipe.base_linux.arn
}

output "infrastructure_config_arn" {
  description = "ARN of the Image Builder infrastructure configuration (instance type, subnet, logging)."
  value       = aws_imagebuilder_infrastructure_configuration.golden_ami.arn
}

output "distribution_config_arn" {
  description = "ARN of the multi-region distribution configuration (us-east-1, eu-west-1, ap-southeast-1)."
  value       = aws_imagebuilder_distribution_configuration.multi_region.arn
}

# ── Networking ────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID of the Image Builder VPC."
  value       = module.image_builder_vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used for Image Builder build instances."
  value       = module.image_builder_vpc.private_subnets
}

# ── Encryption ────────────────────────────────────────────────────────────────

output "kms_key_arn_primary" {
  description = "ARN of the primary KMS key (us-east-1). Used for EBS encryption on built AMIs."
  value       = module.ami_encryption.arn
}

output "kms_key_id_primary" {
  description = "Key ID of the primary KMS key. Used in CloudWatch alarm dimensions."
  value       = module.ami_encryption.key_id
}

output "kms_key_arn_eu_west" {
  description = "ARN of the eu-west-1 KMS replica key. Passed to consumers launching AMIs in eu-west-1."
  value       = aws_kms_replica_key.ami_encryption_eu_west.arn
}

output "kms_key_arn_ap_southeast" {
  description = "ARN of the ap-southeast-1 KMS replica key. Passed to consumers launching AMIs in ap-southeast-1."
  value       = aws_kms_replica_key.ami_encryption_ap_southeast.arn
}

# ── Storage ───────────────────────────────────────────────────────────────────

output "artifacts_bucket_name" {
  description = "Name of the S3 bucket storing Image Builder logs and build artifacts."
  value       = module.ami_artifacts.id
}

output "artifacts_bucket_arn" {
  description = "ARN of the S3 artifacts bucket. Add this to consumer IAM policies that need to read build logs."
  value       = module.ami_artifacts.arn
}

# ── Notifications ─────────────────────────────────────────────────────────────

output "sns_topic_arn" {
  description = "ARN of the SNS topic for AMI pipeline events, Inspector findings, and Security Hub alerts. Subscribe additional endpoints here."
  value       = module.ami_events_sns.topic_arn
}

# ── Compliance ────────────────────────────────────────────────────────────────

output "config_recorder_id_primary" {
  description = "ID of the AWS Config recorder in the primary region."
  value       = aws_config_configuration_recorder.main.id
}

output "cloudtrail_arn" {
  description = "ARN of the multi-region CloudTrail trail."
  value       = aws_cloudtrail.ami_factory.arn
}