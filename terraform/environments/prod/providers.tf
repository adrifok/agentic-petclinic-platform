# AWS provider — prod environment
# Common tags applied to every taggable resource via default_tags, per
# docs/technical-spec.md#general-project-parameters.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
