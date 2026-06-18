# --------------------------------------------------------------------------------
# Getting project information
# --------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------------------
module "image_builder_vpc" {
  source                  = "./modules/vpc"
  vpc_name                = "image-builder-vpc"
  vpc_cidr                = "10.0.0.0/16"
  azs                     = var.azs
  public_subnets          = var.public_subnets
  private_subnets         = var.private_subnets
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false
  tags = {
    Name      = "image-builder-vpc"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# --------------------------------------------------------------------------------
# IAM Role for EC2 Image Builder
# --------------------------------------------------------------------------------
module "image_builder_role" {
  source             = "./modules/iam"
  role_name          = "ec2-image-builder-role"
  role_description   = "IAM role for Image Builder"
  policy_name        = "ec2-image-builder-role-policy"
  policy_description = "IAM policy for Image Builder"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "ec2.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "kms:GenerateDataKey",
                  "kms:Decrypt",
                  "kms:ReEncrypt*",
                  "kms:DescribeKey",
                  "kms:CreateGrant"
                ],
                "Resource": [
                  "${module.ami_encryption.arn}",
                  "${aws_kms_replica_key.ami_encryption_eu_west.arn}",
                  "${aws_kms_replica_key.ami_encryption_ap_southeast.arn}"
                ],
                "Effect": "Allow"
            },
            {
                "Action": [
                  "s3:PutObject",
                  "s3:GetObject",
                  "s3:GetBucketLocation",
                  "s3:ListBucket"
                ],
                "Resource": [
                  "${module.ami_artifacts.arn}",
                  "${module.ami_artifacts.arn}/*"
                ],
                "Effect": "Allow"
            }
        ]
    }
    EOF
  tags = {
    Name = "ami-factory-cloudtrail-cw-role"
  }
}

resource "aws_iam_role_policy_attachment" "image_builder_policy_attachment" {
  role       = module.image_builder_role.name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = module.image_builder_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "image_builder" {
  name = "EC2ImageBuilderInstanceProfile"
  role = module.image_builder_role.name
}

# --------------------------------------------------------------------------------
# Security Groups for Image Builder instances
# --------------------------------------------------------------------------------
module "image_builder_sg" {
  source        = "./modules/security-groups"
  name          = "image-builder-sg"
  vpc_id        = module.image_builder_vpc.vpc_id
  ingress_rules = []
  egress_rules = [
    {
      description = "Allow all outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name      = "image-builder-sg"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# --------------------------------------------------------------------------------
# S3 Bucket for build artifacts
# --------------------------------------------------------------------------------
module "ami_artifacts" {
  source      = "./modules/s3"
  bucket_name = "ami-artifacts-${data.aws_caller_identity.current.account_id}"
  objects     = []
  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::ami-artifacts-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::ami-artifacts-${data.aws_caller_identity.current.account_id}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  versioning_enabled = "Enabled"
  force_destroy      = true
  tags = {
    Name      = "ami-artifacts-${data.aws_caller_identity.current.account_id}"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# --------------------------------------------------------------------------------
# Image Builder Infrastructure
# --------------------------------------------------------------------------------
resource "aws_imagebuilder_infrastructure_configuration" "golden_ami" {
  name                          = "golden-ami-config"
  description                   = "Infrastructure config for Golden AMI builds"
  instance_profile_name         = aws_iam_instance_profile.image_builder.name
  instance_types                = ["m5.large", "m5.xlarge"]
  security_group_ids            = [module.image_builder_sg.id]
  subnet_id                     = module.image_builder_vpc.private_subnets[0]
  terminate_instance_on_failure = true
  logging {
    s3_logs {
      s3_bucket_name = module.ami_artifacts.id
      s3_key_prefix  = "logs"
    }
  }
  tags = {
    Name      = "golden-ami-config"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# --------------------------------------------------------------------------------
# Golden AMI Recipe
# --------------------------------------------------------------------------------
module "ami_encryption" {
  source                  = "./modules/kms"
  name                    = "ami-encryption-key"
  description             = "KMS key for AMI EBS encryption"
  multi_region            = true
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags = {
    Name = "ami-encryption-key"
  }
}

resource "aws_kms_replica_key" "ami_encryption_eu_west" {
  provider                = aws.eu_west
  description             = "KMS replica key for AMI EBS encryption — eu-west-1"
  primary_key_arn         = module.ami_encryption.arn
  deletion_window_in_days = 30
  enabled                 = true
  tags = {
    Name      = "ami-encryption-key-eu-west-1"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

resource "aws_kms_replica_key" "ami_encryption_ap_southeast" {
  provider                = aws.ap_southeast
  description             = "KMS replica key for AMI EBS encryption — ap-southeast-1"
  primary_key_arn         = module.ami_encryption.arn
  deletion_window_in_days = 30
  enabled                 = true
  tags = {
    Name      = "ami-encryption-key-ap-southeast-1"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

resource "aws_kms_key_policy" "ami_encryption" {
  key_id = module.ami_encryption.key_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # ── 1. Root account retains full administrative control ──────────────────
      {
        Sid    = "EnableRootAdminAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },

      # ── 2. CloudWatch Logs (log group encryption) ────────────────────────────
      # Required by: /aws/cloudtrail/ami-factory  and  /aws/imagebuilder/ami-factory
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.primary_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.primary_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },

      # ── 3. CloudTrail (trail log encryption) ─────────────────────────────────
      # Required by: aws_cloudtrail.ami_factory
      {
        Sid    = "AllowCloudTrailEncrypt"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
          }
        }
      },

      # ── 4. Image Builder IAM role (EBS encryption + S3 artifact uploads) ─────
      # Mirrors the inline policy on aws_iam_role_policy.image_builder_kms but
      # the key policy must also permit these actions for them to succeed.
      {
        Sid    = "AllowImageBuilderRole"
        Effect = "Allow"
        Principal = {
          AWS = module.image_builder_role.arn
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_imagebuilder_image_recipe" "base_linux" {
  name         = "base-linux-recipe"
  parent_image = "arn:aws:imagebuilder:${var.primary_region}:aws:image/ubuntu-server-24-lts-x86/x.x.x"
  version      = var.recipe_version

  block_device_mapping {
    device_name = "/dev/xvda"
    ebs {
      delete_on_termination = true
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = module.ami_encryption.arn
    }
  } 

  component {
    component_arn = "arn:aws:imagebuilder:${var.primary_region}:aws:component/update-linux/1.0.2"
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.primary_region}:aws:component/amazon-cloudwatch-agent-linux/1.0.1"
  }

  component {
    component_arn = aws_imagebuilder_component.security_hardening.arn
  }

  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name      = "base-linux-recipe"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# --------------------------------------------------------------------------------
# Custom Component for Security Hardening
# --------------------------------------------------------------------------------
resource "aws_imagebuilder_component" "security_hardening" {
  name     = "security-hardening"
  platform = "Linux"
  version  = "1.0.0"
  data     = file("${path.module}/components/security_hardening.yaml")
  tags = {
    Name      = "security-hardening"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# --------------------------------------------------------------------------------
# Distribution Settings
# --------------------------------------------------------------------------------
resource "aws_imagebuilder_distribution_configuration" "multi_region" {
  name = "multi-region-distribution"

  distribution {
    region = var.primary_region
    ami_distribution_configuration {
      name       = "golden-ami-{{ imagebuilder:buildDate }}"
      kms_key_id = module.ami_encryption.arn # us-east-1 primary key
      ami_tags = {
        SourceAMI   = "{{ imagebuilder:sourceImage }}"
        BuildDate   = "{{ imagebuilder:buildDate }}"
        Environment = "production"
        Project     = var.project
        ManagedBy   = "terraform"
      }
      launch_permission {
        user_ids = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  distribution {
    region = "eu-west-1"
    ami_distribution_configuration {
      name       = "golden-ami-{{ imagebuilder:buildDate }}"
      kms_key_id = aws_kms_replica_key.ami_encryption_eu_west.arn # eu-west-1 replica key
      ami_tags = {
        SourceAMI = "{{ imagebuilder:sourceImage }}"
        BuildDate = "{{ imagebuilder:buildDate }}"
        Project   = var.project
        ManagedBy = "terraform"
      }
      launch_permission {
        user_ids = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  distribution {
    region = "ap-southeast-1"
    ami_distribution_configuration {
      name       = "golden-ami-{{ imagebuilder:buildDate }}"
      kms_key_id = aws_kms_replica_key.ami_encryption_ap_southeast.arn # ap-southeast-1 replica key
      ami_tags = {
        SourceAMI = "{{ imagebuilder:sourceImage }}"
        BuildDate = "{{ imagebuilder:buildDate }}"
        Project   = var.project
        ManagedBy = "terraform"
      }
      launch_permission {
        user_ids = [data.aws_caller_identity.current.account_id]
      }
    }
  }
}

# --------------------------------------------------------------------------------
# Image Pipeline
# --------------------------------------------------------------------------------
resource "aws_imagebuilder_image_pipeline" "golden_ami" {
  name                             = "golden-ami-pipeline"
  description                      = "Pipeline for building Golden AMIs"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.base_linux.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.golden_ami.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.multi_region.arn
  schedule {
    schedule_expression                = "cron(0 0 ? * SUN *)" # Weekly builds
    pipeline_execution_start_condition = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"
  }
  enhanced_image_metadata_enabled = true
  status                          = "ENABLED"
  image_scanning_configuration {
    image_scanning_enabled = true
  }
  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = 60
  }
  tags = {
    Name      = "golden-ami-pipeline"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# --------------------------------------------------------------------------------
# AMI Lifecycle Policy
# --------------------------------------------------------------------------------
resource "aws_imagebuilder_lifecycle_policy" "golden_ami" {
  name           = "golden-ami-lifecycle"
  description    = "Deprecate AMIs older than 90 days, delete after 180"
  execution_role = aws_iam_role.lifecycle_policy.arn
  resource_type  = "AMI_IMAGE"
  status         = "ENABLED"

  policy_detail {
    action {
      type = "DEPRECATE"
    }
    filter {
      type  = "AGE"
      value = 90
      unit  = "DAYS"
    }
  }

  policy_detail {
    action {
      type = "DELETE"
    }
    filter {
      type  = "AGE"
      value = 180
      unit  = "DAYS"
    }
    # Don't delete if the AMI is still in use
    exclusion_rules {
      amis {
        is_public = false
        last_launched {
          value = 90
          unit  = "DAYS"
        }
      }
    }
  }

  resource_selection {
    tag_map = {
      Project = var.project
    }
  }

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# --------------------------------------------------------------------------------
# SNS Topic
# --------------------------------------------------------------------------------
module "ami_events_sns" {
  source     = "./modules/sns"
  topic_name = "ami-creation-notifications"
  subscriptions = [
    {
      protocol = "email"
      endpoint = var.notification_email
    }
  ]
  tags = {
    Name      = "golden-ami-pipeline"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# --------------------------------------------------------------------------------
# EventBridge Rule for AMI Creation Notifications
# --------------------------------------------------------------------------------
module "ami_events_rule" {
  source      = "./modules/eventbridge"
  rule_name   = "ami-creation-event"
  description = "Capture AMI creation events"
  event_pattern = jsonencode({
    source      = ["aws.imagebuilder"]
    detail-type = ["Image Builder Image State Change"]
    detail = {
      state = {
        status = ["AVAILABLE", "FAILED", "CANCELLED"]
      }
    }
  })
  target_id  = "SendToSNS"
  target_arn = module.ami_events_sns.topic_arn
  tags = {
    Name      = "ami-creation-event"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# ---------------------------------------------------------------------------------
# Detect non-compliant / unencrypted AMIs across the account
# ---------------------------------------------------------------------------------
resource "aws_config_configuration_recorder" "main" {
  name     = "ami-factory-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types = [
      "AWS::EC2::Instance",
      "AWS::EC2::Volume",
      "AWS::ImageBuilder::ImagePipeline",
      "AWS::IAM::Role",
      "AWS::S3::Bucket",
    ]
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "ami-factory-delivery"
  s3_bucket_name = module.config_logs.id
  depends_on     = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name = "ami-factory-encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Project = var.project
  }
}

resource "aws_config_config_rule" "approved_amis_by_tag" {
  name = "ami-factory-approved-amis"

  source {
    owner             = "AWS"
    source_identifier = "APPROVED_AMIS_BY_TAG"
  }

  input_parameters = jsonencode({
    amisByTagKeyAndValue = "Project:${var.project}"
  })

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Project = var.project
  }
}

module "config_logs" {
  source      = "./modules/s3"
  bucket_name = "aws-config-ami-factory-${data.aws_caller_identity.current.account_id}"
  objects     = []
  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = module.config_logs.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${module.config_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          module.config_logs.arn,
          "${module.config_logs.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  versioning_enabled = "Disabled"
  force_destroy      = true
  tags = {
    Name = "aws-config-ami-factory-${data.aws_caller_identity.current.account_id}"
  }
}

resource "aws_iam_role" "config_role" {
  name = "ami-factory-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })

  tags = {
    Project = var.project
  }
}

resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role" "lifecycle_policy" {
  name = "ami-factory-lifecycle-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "imagebuilder.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "ami-factory-lifecycle-role"
    Project = var.project
  }
}

resource "aws_iam_role_policy" "lifecycle_policy" {
  name = "ami-factory-lifecycle-policy"
  role = aws_iam_role.lifecycle_policy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DeregisterImage",
          "ec2:DescribeImages",
          "ec2:DeleteSnapshot",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------------
# CLOUDTRAIL — Full API audit trail for all Image Builder + KMS + S3 activity
# ---------------------------------------------------------------------------------
resource "aws_cloudtrail" "ami_factory" {
  name                          = "ami-factory-trail"
  s3_bucket_name                = module.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = module.ami_encryption.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Track all S3 data events on the artifacts bucket
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${module.ami_artifacts.arn}/"]
    }
  }

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = module.cloudtrail_cw_role.arn

  tags = {
    Name    = "ami-factory-trail"
    Project = var.project
  }

  depends_on = [module.cloudtrail_logs]
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/ami-factory"
  retention_in_days = 90
  kms_key_id        = module.ami_encryption.arn

  tags = {
    Project = var.project
  }
  depends_on = [module.ami_encryption]
}

module "cloudtrail_logs" {
  source      = "./modules/s3"
  bucket_name = "cloudtrail-ami-factory-${data.aws_caller_identity.current.account_id}"
  objects     = []
  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = module.cloudtrail_logs.arn
        Condition = {
          StringEquals = { "AWS:SourceArn" = "arn:aws:cloudtrail:${var.primary_region}:${data.aws_caller_identity.current.account_id}:trail/ami-factory-trail" }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${module.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${var.primary_region}:${data.aws_caller_identity.current.account_id}:trail/ami-factory-trail"
          }
        }
      },
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          module.cloudtrail_logs.arn,
          "${module.cloudtrail_logs.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  versioning_enabled = "Disabled"
  force_destroy      = true
  tags = {
    Name = "cloudtrail-ami-factory-${data.aws_caller_identity.current.account_id}"
  }
}

module "cloudtrail_cw_role" {
  source             = "./modules/iam"
  role_name          = "ami-factory-cloudtrail-cw-role"
  role_description   = "IAM role for Cloudtrail logs"
  policy_name        = "cloudtrail-cw-logs-policy"
  policy_description = "IAM policy for Cloudtrail logs"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "cloudtrail.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "logs:PutLogEvents",
                  "logs:CreateLogStream"
                ],
                "Resource": [
                  "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
                ],
                "Effect": "Allow"
            }
        ]
    }
    EOF
  tags = {
    Name = "ami-factory-cloudtrail-cw-role"
  }
}

# ---------------------------------------------------------------------------------
# INSPECTOR V2 — Continuous vulnerability scanning on build instances
# ---------------------------------------------------------------------------------
resource "aws_inspector2_enabler" "ami_factory" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2"]
}

# SNS alert when Inspector finds a CRITICAL finding
module "ami_factory_inspector_events_rule" {
  source      = "./modules/eventbridge"
  rule_name   = "ami-factory-inspector-critical"
  description = "Alert on Inspector CRITICAL findings during AMI builds"
  event_pattern = jsonencode({
    source      = ["aws.inspector2"]
    detail-type = ["Inspector2 Finding"]
    detail = {
      severity = ["CRITICAL", "HIGH"]
      status   = ["ACTIVE"]
      resources = {
        type = ["AWS_EC2_INSTANCE"]
      }
    }
  })
  target_id  = "InspectorCriticalToSNS"
  target_arn = module.ami_events_sns.topic_arn
  tags = {
    Name      = "ami-factory-inspector-critical"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# ---------------------------------------------------------------------------------
# CLOUDWATCH ALARMS — Pipeline health monitoring
# ---------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "image_builder" {
  name              = "/aws/imagebuilder/ami-factory"
  retention_in_days = 90
  kms_key_id        = module.ami_encryption.arn

  tags = {
    Project = var.project
  }
  depends_on = [module.ami_encryption]
}

# Metric filter: count pipeline FAILED events from EventBridge logs
resource "aws_cloudwatch_log_metric_filter" "pipeline_failures" {
  name           = "ami-pipeline-failures"
  log_group_name = aws_cloudwatch_log_group.image_builder.name
  pattern        = "{ $.detail.state.status = \"FAILED\" }"

  metric_transformation {
    name      = "PipelineFailures"
    namespace = "AMIFactory/ImageBuilder"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_imagebuilder" {
  policy_name = "eventbridge-ami-factory-imagebuilder-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeWrite"
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "delivery.logs.amazonaws.com"
          ]
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.image_builder.arn}:*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:events:${var.primary_region}:${data.aws_caller_identity.current.account_id}:rule/ami-creation-event"
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "imagebuilder_to_cwlogs" {
  rule      = module.ami_events_rule.rule_name
  target_id = "ImageBuilderStateToCWLogs"
  arn       = aws_cloudwatch_log_group.image_builder.arn

  depends_on = [
    aws_cloudwatch_log_resource_policy.eventbridge_imagebuilder
  ]
}

module "pipeline_failures" {
  source              = "./modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "ami-factory-pipeline-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PipelineFailures"
  namespace           = "AMIFactory/ImageBuilder"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Image Builder pipeline failed. Check /aws/imagebuilder/ami-factory logs. Common causes: component script error, Inspector test failure, or KMS key access denied during EBS encryption."
  alarm_actions       = [module.ami_events_sns.topic_arn]
  ok_actions          = [module.ami_events_sns.topic_arn]
}

# KMS key usage anomaly — unexpected spikes = possible unauthorized decryption
module "kms_key_usage_spike" {
  source              = "./modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "ami-factory-kms-usage-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "NumberOfRequestsSucceeded"
  namespace           = "AWS/KMS"
  period              = 300
  statistic           = "Sum"
  threshold           = 500
  alarm_description   = "Unusual KMS Decrypt/GenerateDataKey volume on ami-encryption-key. May indicate unauthorized AMI access or unexpected launch activity in non-production accounts."
  alarm_actions       = [module.ami_events_sns.topic_arn]
  ok_actions          = [module.ami_events_sns.topic_arn]

  dimensions = {
    KeyId = module.ami_encryption.key_id
  }
}

# S3 artifacts bucket — 4XX errors = broken component download during builds
module "ami_artifacts_s3_4xx" {
  source              = "./modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "ami-factory-artifacts-4xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "S3 4XX errors on ami-artifacts bucket. Image Builder component downloads may be failing. Check bucket policy and IAM role permissions on ec2-image-builder-role."
  alarm_actions       = [module.ami_events_sns.topic_arn]
  ok_actions          = [module.ami_events_sns.topic_arn]

  dimensions = {
    BucketName = module.ami_artifacts.id
    FilterId   = "EntireBucket"
  }
}

# ---------------------------------------------------------------------------------
# SECURITY HUB — Aggregate Config, Inspector, CloudTrail findings in one place
# ---------------------------------------------------------------------------------
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:${var.primary_region}::standards/cis-aws-foundations-benchmark/v/3.0.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:aws:securityhub:${var.primary_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}

# Route CRITICAL Security Hub findings to SNS
module "securityhub_critical" {
  source      = "./modules/eventbridge"
  rule_name   = "securityhub-critical-event"
  description = "Capture Security Hub events"
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL", "HIGH"]
        }
        RecordState   = ["ACTIVE"]
        WorkflowState = ["NEW"]
      }
    }
  })
  target_id  = "SecurityHubCriticalToSNS"
  target_arn = module.ami_events_sns.topic_arn
  tags = {
    Name      = "securityhub-critical-event"
    ManagedBy = "terraform"
    Project   = var.project
  }
}
