# Module: karpenter
# AWS-side prerequisites for Karpenter node autoscaling: controller IRSA role
# + policy, instance profile for Karpenter-launched nodes, SQS interruption
# queue, and the EventBridge rules that feed it. The Karpenter Helm release,
# NodePool and EC2NodeClass are installed separately (kube-system).
#
# Implements PETPLAT-73 (AWS resources). See
# docs/technical-spec.md#karpenter-node-autoscaling and #irsa-roles.
#
# The controller policy follows the upstream Karpenter v1 reference policy
# instead of the spec's shorthand (ec2:*, sqs:*): EC2 write actions are
# scoped to resources tagged kubernetes.io/cluster/{cluster}=owned plus a
# karpenter.sh/nodepool tag, SQS to this queue only, and iam:PassRole to the
# node role only. Instance-profile management actions are omitted because the
# EC2NodeClass references the pre-created profile below (spec.instanceProfile)
# rather than a role.

locals {
  name_prefix = "${var.project}-${var.environment}"

  # {oidc-provider} value for IRSA trust policy conditions — the issuer URL
  # without its https:// scheme.
  oidc_provider_id = replace(var.oidc_provider_url, "https://", "")

  service_account_namespace = "kube-system"
  service_account_name      = "karpenter"

  node_role_name = element(split("/", var.node_role_arn), length(split("/", var.node_role_arn)) - 1)

  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id

  cluster_tag_key = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
  cluster_req_key = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"

  # Resources Karpenter creates when launching a node.
  ec2_launch_resource_arns = [
    for r in ["fleet", "instance", "volume", "network-interface", "launch-template", "spot-instances-request"] :
    "arn:${local.partition}:ec2:${local.region}:*:${r}/*"
  ]

  interruption_events = {
    spot-interruption = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance Rebalance Recommendation"]
    }
    instance-state-change = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
    }
    scheduled-change = {
      source      = ["aws.health"]
      detail-type = ["AWS Health Event"]
    }
  }
}

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Node instance profile
# ---------------------------------------------------------------------------

# Reuses the managed node group's role. EKS auto-creates an EC2_LINUX access
# entry for it (not in Terraform; verified on dev 2026-10-10), so Karpenter
# nodes can join without a new entry. If the managed node group is ever
# removed, add an aws_eks_access_entry of type EC2_LINUX for this role.
# Name is referenced verbatim by the EC2NodeClass — do not change.
resource "aws_iam_instance_profile" "node" {
  name = "${local.name_prefix}-karpenter-node-profile"
  role = local.node_role_name

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-karpenter-node-profile"
  })
}

# ---------------------------------------------------------------------------
# SQS interruption queue + EventBridge rules
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "interruption" {
  name                       = "${local.name_prefix}-karpenter-interruption"
  message_retention_seconds  = 300
  visibility_timeout_seconds = 1200
  sqs_managed_sse_enabled    = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-karpenter-interruption"
  })
}

# Without this policy EventBridge cannot deliver to the queue and Karpenter
# never sees spot interruptions. Scoped to this module's rules via SourceArn.
data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid       = "AllowEventBridgeSendMessage"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for r in aws_cloudwatch_event_rule.interruption : r.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_events

  name          = "${local.name_prefix}-karpenter-${each.key}"
  description   = "Routes ${each.value["detail-type"][0]} events to the Karpenter interruption queue."
  event_pattern = jsonencode(each.value)

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-karpenter-${each.key}"
  })
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = aws_cloudwatch_event_rule.interruption

  rule      = each.value.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

# ---------------------------------------------------------------------------
# Controller IRSA role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "controller_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_id}:sub"
      values   = ["system:serviceaccount:${local.service_account_namespace}:${local.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_id}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "controller" {
  # Launch inputs Karpenter does not own (AMIs, subnets, SGs, snapshots).
  statement {
    sid     = "AllowScopedEC2InstanceAccessActions"
    effect  = "Allow"
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}::image/*",
      "arn:${local.partition}:ec2:${local.region}::snapshot/*",
      "arn:${local.partition}:ec2:${local.region}:*:security-group/*",
      "arn:${local.partition}:ec2:${local.region}:*:subnet/*",
      "arn:${local.partition}:ec2:${local.region}:*:capacity-reservation/*",
    ]
  }

  statement {
    sid       = "AllowScopedEC2LaunchTemplateAccessActions"
    effect    = "Allow"
    actions   = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = ["arn:${local.partition}:ec2:${local.region}:*:launch-template/*"]

    condition {
      test     = "StringEquals"
      variable = local.cluster_tag_key
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedEC2InstanceActionsWithTags"
    effect    = "Allow"
    actions   = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
    resources = local.ec2_launch_resource_arns

    condition {
      test     = "StringEquals"
      variable = local.cluster_req_key
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedResourceCreationTagging"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = local.ec2_launch_resource_arns

    condition {
      test     = "StringEquals"
      variable = local.cluster_req_key
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedResourceTagging"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${local.partition}:ec2:${local.region}:*:instance/*"]

    condition {
      test     = "StringEquals"
      variable = local.cluster_tag_key
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
    }
  }

  statement {
    sid     = "AllowScopedDeletion"
    effect  = "Allow"
    actions = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
    ]

    condition {
      test     = "StringEquals"
      variable = local.cluster_tag_key
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # EC2 Describe* actions do not support resource-level permissions.
  statement {
    sid    = "AllowRegionalReadActions"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeCapacityReservations",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid       = "AllowSSMReadActions"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${local.region}::parameter/aws/service/*"]
  }

  # pricing:GetProducts does not support resource-level permissions.
  statement {
    sid       = "AllowPricingReadActions"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowInterruptionQueueActions"
    effect    = "Allow"
    actions   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
    resources = [aws_sqs_queue.interruption.arn]
  }

  # PassRole is evaluated against the role inside the instance profile, so it
  # is scoped to that one role (not the profile ARN, which PassRole ignores).
  statement {
    sid       = "AllowPassingInstanceRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [var.node_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "AllowInstanceProfileReadActions"
    effect    = "Allow"
    actions   = ["iam:GetInstanceProfile"]
    resources = [aws_iam_instance_profile.node.arn]
  }

  statement {
    sid       = "AllowAPIServerEndpointDiscovery"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.cluster_name}"]
  }
}

resource "aws_iam_policy" "controller" {
  name        = "${local.name_prefix}-karpenter-policy"
  description = "Karpenter controller permissions, scoped to ${var.cluster_name}."
  policy      = data.aws_iam_policy_document.controller.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-karpenter-policy"
  })
}

resource "aws_iam_role" "controller" {
  name               = "${local.name_prefix}-karpenter-role"
  assume_role_policy = data.aws_iam_policy_document.controller_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-karpenter-role"
  })
}

resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}
