# --------------------------------------------------------------------------------
# Container Recipe & Pipeline Variables
# --------------------------------------------------------------------------------

variable "enable_container_recipe" {
  description = "Whether to provision the EC2 Image Builder Container Recipe and ECR infrastructure"
  type        = bool
  default     = true
}

variable "container_recipe_version" {
  description = "Semantic version of the container recipe (immutable in AWS Image Builder)"
  type        = string
  default     = "1.0.0"
}

variable "container_parent_image" {
  description = "Base container image to build from (e.g. public.ecr.aws/ubuntu/ubuntu:24.04 or ubuntu:24.04)"
  type        = string
  default     = "public.ecr.aws/ubuntu/ubuntu:24.04"
}

variable "container_repository_name" {
  description = "Name of the Amazon ECR repository for golden container images"
  type        = string
  default     = "golden-container"
}

variable "container_image_tag_mutability" {
  description = "The tag mutability setting for the ECR repository (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "enable_container_pipeline" {
  description = "Whether to create the scheduled automated Image Builder pipeline for containers"
  type        = bool
  default     = true
}
