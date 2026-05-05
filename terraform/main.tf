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
  enable_nat_gateway      = false
  single_nat_gateway      = false
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
        Resource = aws_kms_key.ami_encryption.arn
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
resource "aws_kms_key" "ami_encryption" {
  description             = "KMS key for AMI EBS encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags = {
    Name      = "ami-encryption-key"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

resource "aws_kms_alias" "ami_encryption" {
  name          = "alias/ami-encryption-key"
  target_key_id = aws_kms_key.ami_encryption.key_id
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
      kms_key_id            = aws_kms_key.ami_encryption.arn
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
      kms_key_id = aws_kms_key.ami_encryption.arn # ← add this
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
      kms_key_id = aws_kms_key.ami_encryption.arn
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
      kms_key_id = aws_kms_key.ami_encryption.arn
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
module "eventbridge_rule" {
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