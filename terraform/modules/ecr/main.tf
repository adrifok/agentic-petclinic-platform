# Module: ecr
# One private ECR repository per microservice, under the petclinic-{env}/
# namespace, with scan-on-push and configurable tag immutability. A lifecycle
# policy expires untagged images after a few days and caps total image count
# per repository.
#
# Implements PETPLAT-18 (repositories) and PETPLAT-19 (lifecycle policy +
# tag immutability). See docs/technical-spec.md#ecr-container-registry.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.service_names)

  name                 = "${var.project}-${var.environment}/${each.value}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-${each.value}"
  })
}

# Two independent rules — AWS evaluates each tagStatus family on its own, so
# these don't conflict despite sharing a repository:
#   1. untagged images older than N days are expired first (dangling layers
#      from repeated dev pushes of the same tag)
#   2. total image count across any tag status is capped at N — the
#      "keep last N images" rule from docs/technical-spec.md#ecr-container-registry
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.max_image_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = { type = "expire" }
      }
    ]
  })
}
