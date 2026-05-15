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
resource "aws_iam_role" "image_builder" {
  name = "ec2-image-builder-role"
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
  tags = {
    Name      = "ec2-image-builder-role"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

resource "aws_iam_role_policy_attachment" "image_builder_policy_attachment" {
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

resource "aws_iam_role_policy" "image_builder_kms" {
  name = "ec2-image-builder-kms-policy"
  role = aws_iam_role.image_builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = module.ami_encryption.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          module.ami_artifacts.arn,
          "${module.ami_artifacts.arn}/*"
        ]
      }
    ]
  })
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
      allowed_origins = ["https://*.amazonaws.com"]
      max_age_seconds = 3000
    }
  ]
  versioning_enabled = "Enabled"
  force_destroy      = false
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
  # key_pair                      = var.key_pair_name
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
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags = {
    Name      = "ami-encryption-key"
  }
}

resource "aws_imagebuilder_image_recipe" "base_linux" {
  name         = "base-linux-recipe"
  parent_image = "arn:aws:imagebuilder:${var.primary_region}:aws:image/amazon-linux-2-x86/x.x.x"
  version      = "1.0.0"

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
    component_arn = "arn:aws:imagebuilder:${var.primary_region}:aws:component/inspector-test-linux/x.x.x"
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
  data     = <<EOF
name: SecurityHardening
description: CIS-aligned security hardening for golden AMI
schemaVersion: 1.0
phases:
  - name: build
    steps:
      # ── SSH hardening ──────────────────────────────────────────
      - name: HardenSSH
        action: ExecuteBash
        inputs:
          commands:
            - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
            - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
            - sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
            - sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
            - sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
            - sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
            - sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config
            - echo "Protocol 2" >> /etc/ssh/sshd_config
            - echo "AllowTcpForwarding no" >> /etc/ssh/sshd_config
            - echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
            - echo "MACs hmac-sha2-256,hmac-sha2-512" >> /etc/ssh/sshd_config
            - systemctl restart sshd

      # ── Kernel hardening (sysctl) ──────────────────────────────
      - name: HardenKernel
        action: ExecuteBash
        inputs:
          commands:
            - |
              cat > /etc/sysctl.d/99-hardening.conf << 'SYSCTL'
              # Prevent IP spoofing
              net.ipv4.conf.all.rp_filter = 1
              net.ipv4.conf.default.rp_filter = 1
              # Disable IP source routing
              net.ipv4.conf.all.accept_source_route = 0
              net.ipv4.conf.default.accept_source_route = 0
              # Disable ICMP redirects
              net.ipv4.conf.all.accept_redirects = 0
              net.ipv4.conf.default.accept_redirects = 0
              net.ipv4.conf.all.send_redirects = 0
              # Enable SYN flood protection
              net.ipv4.tcp_syncookies = 1
              # Disable IPv6 if not needed
              net.ipv6.conf.all.disable_ipv6 = 1
              net.ipv6.conf.default.disable_ipv6 = 1
              # Restrict core dumps
              fs.suid_dumpable = 0
              # Hide kernel pointers
              kernel.kptr_restrict = 2
              # Restrict dmesg access
              kernel.dmesg_restrict = 1
              # Prevent ptrace abuse
              kernel.yama.ptrace_scope = 1
              SYSCTL
            - sysctl -p /etc/sysctl.d/99-hardening.conf

      # ── Password and account policies ─────────────────────────
      - name: PasswordPolicy
        action: ExecuteBash
        inputs:
          commands:
            - sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' /etc/login.defs
            - sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS 7/' /etc/login.defs
            - sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN 14/' /etc/login.defs
            - sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE 14/' /etc/login.defs
            - authconfig --passalgo=sha512 --update
            # Lock inactive accounts after 30 days
            - useradd -D -f 30

      # ── Disable unnecessary services ──────────────────────────
      - name: DisableServices
        action: ExecuteBash
        inputs:
          commands:
            - for svc in avahi-daemon cups postfix rpcbind nfs bluetooth; do
                systemctl disable $svc 2>/dev/null || true
                systemctl stop $svc 2>/dev/null || true
              done

      # ── Install and configure auditd ──────────────────────────
      - name: ConfigureAuditd
        action: ExecuteBash
        inputs:
          commands:
            - yum install -y audit audit-libs
            - systemctl enable auditd
            - |
              cat > /etc/audit/rules.d/hardening.rules << 'AUDIT'
              # Log all authentication attempts
              -w /etc/passwd -p wa -k identity
              -w /etc/group -p wa -k identity
              -w /etc/shadow -p wa -k identity
              -w /etc/sudoers -p wa -k sudoers
              # Log privileged commands
              -a always,exit -F arch=b64 -S execve -F euid=0 -k privileged
              # Log network configuration changes
              -a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale
              # Log mount operations
              -a always,exit -F arch=b64 -S mount -k mounts
              # Log file deletion
              -a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -k delete
              AUDIT
            - service auditd restart

      # ── Install security and scanning tools ───────────────────
      - name: InstallSecurityTools
        action: ExecuteBash
        inputs:
          commands:
            - yum install -y clamav clamav-update rkhunter aide
            - freshclam
            - rkhunter --update
            - rkhunter --propupd
            # Initialise AIDE database for file integrity monitoring
            - aide --init
            - mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

      # ── Disable USB storage ───────────────────────────────────
      - name: DisableUSB
        action: ExecuteBash
        inputs:
          commands:
            - echo "install usb-storage /bin/true" > /etc/modprobe.d/usb-storage.conf
            - echo "blacklist usb-storage" >> /etc/modprobe.d/blacklist.conf

      # ── Set umask and file permissions ─────────────────────────
      - name: FilePermissions
        action: ExecuteBash
        inputs:
          commands:
            - sed -i 's/^UMASK.*/UMASK 027/' /etc/login.defs
            - chmod 600 /etc/ssh/sshd_config
            - chmod 700 /root
            - chmod 600 /etc/crontab
            - chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly

      # ── Clean up before imaging ────────────────────────────────
      - name: Cleanup
        action: ExecuteBash
        inputs:
          commands:
            - yum clean all
            - rm -rf /var/cache/yum
            - find /var/log -type f -exec truncate -s 0 {} \;
            - rm -f /root/.bash_history
            - find /home -name ".bash_history" -exec rm -f {} \;
            - rm -rf /tmp/* /var/tmp/*

  - name: validate
    steps:
      - name: ValidateHardening
        action: ExecuteBash
        inputs:
          commands:
            - grep -E "^PermitRootLogin no" /etc/ssh/sshd_config || exit 1
            - grep -E "^PasswordAuthentication no" /etc/ssh/sshd_config || exit 1
            - sysctl net.ipv4.tcp_syncookies | grep -q "= 1" || exit 1
            - echo "Hardening validation passed"
EOF
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
      kms_key_id = module.ami_encryption.arn # ← add this
      ami_tags = {
        SourceAMI   = "{{ imagebuilder:sourceImage }}"
        BuildDate   = "{{ imagebuilder:buildDate }}"
        Environment = "production"
        Project     = var.project
        ManagedBy   = "terraform"
      }
      launch_permission {
        # Restrict who can launch from this AMI
        # Only your own account — remove if you need to share cross-account
        user_ids = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  distribution {
    region = "eu-west-1"
    ami_distribution_configuration {
      name       = "golden-ami-{{ imagebuilder:buildDate }}"
      kms_key_id = module.ami_encryption.arn
      ami_tags = {
        SourceAMI = "{{ imagebuilder:sourceImage }}"
        BuildDate = "{{ imagebuilder:buildDate }}"
      }
    }
  }

  distribution {
    region = "ap-southeast-1"
    ami_distribution_configuration {
      name       = "golden-ami-{{ imagebuilder:buildDate }}"
      kms_key_id = module.ami_encryption.arn
      ami_tags = {
        SourceAMI = "{{ imagebuilder:sourceImage }}"
        BuildDate = "{{ imagebuilder:buildDate }}"
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
  execution_role = aws_iam_role.image_builder.arn
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
  s3_bucket_name = aws_s3_bucket.config_logs.id
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

resource "aws_s3_bucket" "config_logs" {
  bucket        = "aws-config-ami-factory-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Name    = "aws-config-ami-factory-logs"
    Project = var.project
  }
}

resource "aws_s3_bucket_public_access_block" "config_logs" {
  bucket                  = aws_s3_bucket.config_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_logs.arn
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
        Resource = "${aws_s3_bucket.config_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
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

# ---------------------------------------------------------------------------------
# CLOUDTRAIL — Full API audit trail for all Image Builder + KMS + S3 activity
# ---------------------------------------------------------------------------------
resource "aws_cloudtrail" "ami_factory" {
  name                          = "ami-factory-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
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

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
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

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "cloudtrail-ami-factory-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Name    = "cloudtrail-ami-factory-logs"
    Project = var.project
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail_logs.arn
        Condition = {
          StringEquals = { "AWS:SourceArn" = "arn:aws:cloudtrail:${var.primary_region}:${data.aws_caller_identity.current.account_id}:trail/ami-factory-trail" }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${var.primary_region}:${data.aws_caller_identity.current.account_id}:trail/ami-factory-trail"
          }
        }
      }
    ]
  })
}

module "cloudtrail_cw_role" {
  source             = "./modules/iam"
  role_name          = "ami-factory-cloudtrail-cw-role"
  role_description   = "IAM role for VPC Flow Logs"
  policy_name        = "cloudtrail-cw-logs-policy"
  policy_description = "IAM policy for VPC Flow Logs"
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
  resource_types = ["EC2", "ECR"]
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

resource "aws_cloudwatch_metric_alarm" "pipeline_failures" {
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

  tags = {
    Project = var.project
  }
}

# KMS key usage anomaly — unexpected spikes = possible unauthorized decryption
resource "aws_cloudwatch_metric_alarm" "kms_key_usage_spike" {
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

  tags = {
    Project = var.project
  }
}

# S3 artifacts bucket — 4XX errors = broken component download during builds
resource "aws_cloudwatch_metric_alarm" "artifacts_4xx" {
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

  tags = {
    Project = var.project
  }
}

# ---------------------------------------------------------------------------------
# SECURITY HUB — Aggregate Config, Inspector, CloudTrail findings in one place
# ---------------------------------------------------------------------------------
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
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
    detail-type = ["Image Builder Image State Change"]
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
