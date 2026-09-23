# Module: github-oidc
# IAM OIDC provider for GitHub Actions plus the role the app repo's build
# workflow (build-push.yml) assumes to push images to ECR. No long-lived
# keys: the workflow exchanges its GitHub-issued OIDC token for temporary
# credentials via sts:AssumeRoleWithWebIdentity.
#
# Trust is pinned to one repo + one branch (exact StringEquals on sub), so
# forks, PRs, tags and other branches cannot assume the role.
#
# Implements PETPLAT-52. See docs/technical-spec.md#cicd-pipeline.

locals {
  name              = "${var.project}-${var.environment}-github-actions"
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
  # Repos with GitHub's immutable subject claims enabled send
  # repo:{owner}@{owner_id}/{repo}@{repo_id}:... — the IDs survive renames,
  # so a re-registered owner/repo name can't match. Legacy format otherwise.
  github_repo_path   = var.github_owner_id != "" && var.github_repo_id != "" ? "${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}" : "${var.github_owner}/${var.github_repo}"
  github_sub_subject = "repo:${local.github_repo_path}:ref:refs/heads/${var.github_branch}"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.oidc_thumbprints

  tags = merge(var.tags, {
    Name = "${var.project}-github-actions-oidc"
  })
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_sub_subject]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${local.name}-role"
  description          = "Assumed by ${var.github_owner}/${var.github_repo} (${var.github_branch}) GitHub Actions via OIDC to push images to ${var.project}-${var.environment} ECR."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration

  lifecycle {
    precondition {
      condition     = var.create_oidc_provider || var.existing_oidc_provider_arn != ""
      error_message = "existing_oidc_provider_arn must be set when create_oidc_provider is false."
    }

    precondition {
      condition     = (var.github_owner_id == "") == (var.github_repo_id == "")
      error_message = "github_owner_id and github_repo_id must be set together (immutable OIDC subject) or both left empty (legacy subject)."
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name}-role"
  })
}

data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken does not support resource-level permissions —
  # AWS requires Resource "*" for this single action. It only returns a
  # registry login token; what can be pushed is limited by the statement below.
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushToEnvRepos"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "${local.name}-ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
