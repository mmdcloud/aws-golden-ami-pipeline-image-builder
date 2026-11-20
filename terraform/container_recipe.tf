# ================================================================================
# Production-Grade Container Recipe & Pipeline for AWS EC2 Image Builder
# ================================================================================

# ── 1. Target Amazon ECR Repository ─────────────────────────────────────────────
resource "aws_ecr_repository" "golden_container" {
  count                = var.enable_container_recipe ? 1 : 0
  name                 = var.container_repository_name
  image_tag_mutability = var.container_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = module.ami_encryption.arn
  }

  tags = {
    Name      = var.container_repository_name
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# ── 2. ECR Lifecycle Policy (Cleanup untagged & retain production versions) ─────
resource "aws_ecr_lifecycle_policy" "golden_container" {
  count      = var.enable_container_recipe ? 1 : 0
  repository = aws_ecr_repository.golden_container[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged/dangling images older than 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Retain the last 30 tagged production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "1.", "2.", "latest", "prod"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ── 3. ECR Repository Access Policy ─────────────────────────────────────────────
resource "aws_ecr_repository_policy" "golden_container" {
  count      = var.enable_container_recipe ? 1 : 0
  repository = aws_ecr_repository.golden_container[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "AllowImageBuilderPushPull"
          Effect = "Allow"
          Principal = {
            AWS = module.image_builder_role.arn
          }
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability",
            "ecr:PutImage",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
            "ecr:DescribeRepositories",
            "ecr:GetRepositoryPolicy",
            "ecr:ListImages"
          ]
        }
      ],
      length(var.shared_account_ids) > 0 ? [
        {
          Sid    = "AllowSharedAccountsPull"
          Effect = "Allow"
          Principal = {
            AWS = [for acc in var.shared_account_ids : "arn:aws:iam::${acc}:root"]
          }
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability"
          ]
        }
      ] : []
    )
  })
}

# ── 4. IAM Permission Attachment for Container Builds ───────────────────────────
# AWS Managed policy required for Image Builder instances to interact with ECR
resource "aws_iam_role_policy_attachment" "image_builder_ecr" {
  count      = var.enable_container_recipe ? 1 : 0
  role       = module.image_builder_role.name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
}

# ── 5. Container Security Hardening Component ───────────────────────────────────
resource "aws_imagebuilder_component" "container_security_hardening" {
  count    = var.enable_container_recipe ? 1 : 0
  name     = "container-security-hardening"
  platform = "Linux"
  version  = var.container_recipe_version
  data     = file("${path.module}/components/container_security_hardening.yaml")

  tags = {
    Name      = "container-security-hardening"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# ── 6. EC2 Image Builder Container Recipe ───────────────────────────────────────
resource "aws_imagebuilder_container_recipe" "golden_container" {
  count          = var.enable_container_recipe ? 1 : 0
  name           = "golden-container-recipe"
  version        = var.container_recipe_version
  container_type = "DOCKER"
  parent_image   = var.container_parent_image
  description    = "CIS-aligned production-grade container recipe based on Ubuntu 24.04"

  target_repository {
    service         = "ECR"
    repository_name = aws_ecr_repository.golden_container[0].name
  }

  component {
    component_arn = aws_imagebuilder_component.container_security_hardening[0].arn
  }

  dockerfile_template_data = <<-EOF
    FROM {{{ imagebuilder:parentImage }}}
    LABEL maintainer="Cloud Infrastructure Engineering"
    LABEL org.opencontainers.image.title="Hardened Base Container"
    LABEL org.opencontainers.image.vendor="Enterprise Security"
    LABEL org.opencontainers.image.schema-version="1.0"
    {{{ imagebuilder:environments }}}
    {{{ imagebuilder:components }}}
    USER appuser
    WORKDIR /home/appuser
    CMD ["/bin/bash"]
  EOF

  tags = {
    Name      = "golden-container-recipe"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# ── 7. Container Distribution Configuration ─────────────────────────────────────
resource "aws_imagebuilder_distribution_configuration" "container_distribution" {
  count       = var.enable_container_recipe ? 1 : 0
  name        = "golden-container-distribution"
  description = "Distribution configuration for Golden Container images to ECR"

  distribution {
    region = var.primary_region
    container_distribution_configuration {
      description = "Distribute container image to primary ECR repository"
      target_repository {
        service         = "ECR"
        repository_name = aws_ecr_repository.golden_container[0].name
      }
      container_tags = [
        "latest",
        "{{ buildVersion }}"
      ]
    }
  }

  tags = {
    Name      = "golden-container-distribution"
    ManagedBy = "terraform"
    Project   = var.project
  }
}

# ── 8. Automated Scheduled Pipeline for Golden Containers ───────────────────────
resource "aws_imagebuilder_image_pipeline" "golden_container" {
  count                            = var.enable_container_recipe && var.enable_container_pipeline ? 1 : 0
  name                             = "golden-container-pipeline"
  description                      = "Pipeline for building hardened Golden Container images"
  container_recipe_arn             = aws_imagebuilder_container_recipe.golden_container[0].arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.golden_ami.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.container_distribution[0].arn

  schedule {
    schedule_expression                = "cron(0 0 ? * SUN *)" # Weekly builds
    pipeline_execution_start_condition = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"
  }

  enhanced_image_metadata_enabled = true
  status                          = "ENABLED"

  tags = {
    Name      = "golden-container-pipeline"
    ManagedBy = "terraform"
    Project   = var.project
  }
}
