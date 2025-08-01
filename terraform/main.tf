data "aws_caller_identity" "current" {}

# IAM Role for EC2 Image Builder
resource "aws_iam_role" "image_builder" {
  name = "EC2ImageBuilderRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "image_builder" {
  role       = aws_iam_role.image_builder.name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.image_builder.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "image_builder" {
  name = "EC2ImageBuilderInstanceProfile"
  role = aws_iam_role.image_builder.name
}

# Security Groups for Image Builder instances
resource "aws_security_group" "image_builder" {
  name        = "image-builder-sg"
  description = "Allow outbound traffic for Image Builder"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Image Builder Security Group"
  }
}

# S3 Bucket for build artifacts
module "ami_artifacts" {
  source      = "./modules/s3"
  bucket_name = "ami-artifacts-${data.aws_caller_identity.current.account_id}"
}

# Image Builder Infrastructure
resource "aws_imagebuilder_infrastructure_configuration" "golden_ami" {
  name                          = "golden-ami-config"
  description                   = "Infrastructure config for Golden AMI builds"
  instance_profile_name         = aws_iam_instance_profile.image_builder.name
  instance_types                = ["m5.large", "m5.xlarge"]
  security_group_ids            = [aws_security_group.image_builder.id]
  subnet_id                     = var.subnet_id
  terminate_instance_on_failure = true

  logging {
    s3_logs {
      s3_bucket_name = module.ami_artifacts.id
      s3_key_prefix  = "logs"
    }
  }
}

# Golden AMI Recipe
resource "aws_imagebuilder_image_recipe" "base_linux" {
  name         = "base-linux-recipe"
  parent_image = "arn:aws:imagebuilder:${var.primary_region}:aws:image/amazon-linux-2-x86/x.x.x"
  version      = "1.0.0"

  block_device_mapping {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      volume_size           = 20
      volume_type           = "gp3"
    }
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.primary_region}:aws:component/update-linux/x.x.x"
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.primary_region}:aws:component/amazon-cloudwatch-agent-linux/x.x.x"
  }

  component {
    component_arn = aws_imagebuilder_component.security_hardening.arn
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Custom Component for Security Hardening
resource "aws_imagebuilder_component" "security_hardening" {
  name     = "security-hardening"
  platform = "Linux"
  version  = "1.0.0"

  data = <<EOF
name: SecurityHardening
description: Custom security hardening steps
schemaVersion: 1.0

phases:
  - name: build
    steps:
      - name: DisableRootLogin
        action: ExecuteBash
        inputs:
          commands:
            - sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
            - systemctl restart sshd

      - name: InstallSecurityTools
        action: ExecuteBash
        inputs:
          commands:
            - yum install -y clamav rkhunter
            - freshclam
            - rkhunter --update
            - rkhunter --propupd
EOF
}

# Distribution Settings
resource "aws_imagebuilder_distribution_configuration" "multi_region" {
  name = "multi-region-distribution"

  distribution {
    region = var.primary_region

    ami_distribution_configuration {
      name = "golden-ami-{{ imagebuilder:buildDate }}"
      ami_tags = {
        SourceAMI = "{{ imagebuilder:sourceImage }}"
        BuildDate = "{{ imagebuilder:buildDate }}"
      }
    }
  }

  distribution {
    region = "eu-west-1"

    ami_distribution_configuration {
      name = "golden-ami-{{ imagebuilder:buildDate }}"
      ami_tags = {
        SourceAMI = "{{ imagebuilder:sourceImage }}"
        BuildDate = "{{ imagebuilder:buildDate }}"
      }
    }
  }

  distribution {
    region = "ap-southeast-1"

    ami_distribution_configuration {
      name = "golden-ami-{{ imagebuilder:buildDate }}"
      ami_tags = {
        SourceAMI = "{{ imagebuilder:sourceImage }}"
        BuildDate = "{{ imagebuilder:buildDate }}"
      }
    }
  }
}

# Image Pipeline
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

  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = 60
  }
}

# EventBridge Rule for AMI Creation Notifications
module "eventbridge_rule" {
  source        = "./modules/eventbridge"
  rule_name     = "ami-creation-event"
  description   = "Capture AMI creation events"
  event_pattern = <<EOF
{
  "source": ["aws.imagebuilder"],
  "detail-type": ["Image Builder Image State Change"]
}
EOF 
  target_id     = "SendToSNS"
  target_arn    = module.notification_topic.arn
}

# SNS Topic
module "notification_topic" {
  source     = "./modules/sns"
  topic_name = "ami-creation-notifications"
}