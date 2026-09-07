# Module: eks
# EKS cluster, cluster IAM role, OIDC provider for IRSA, managed node group,
# kubectl access entries, and core managed add-ons (coredns, kube-proxy,
# vpc-cni, aws-ebs-csi-driver).
#
# All-public subnet design — cluster and nodes sit in the public subnets from
# the vpc module, with the vpc module's security groups as the perimeter. See
# ADR-0001 in docs/technical-spec.md#adr-index.
#
# Implements PETPLAT-12 (cluster + IAM roles), PETPLAT-13 (managed node
# group), PETPLAT-14 (kubectl access), and PETPLAT-84 (add-ons).

locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = local.name_prefix

  node_labels = merge(
    {
      environment  = var.environment
      "managed-by" = "terraform"
    },
    var.node_labels
  )

  # {oidc-provider} value for IRSA trust policy conditions — the issuer URL
  # without its https:// scheme.
  oidc_provider_id = replace(aws_iam_openid_connect_provider.this.url, "https://", "")

  # EKS access entries require the IAM user or role ARN, not an STS
  # assumed-role session ARN. Rewrite
  # arn:aws:sts::<acct>:assumed-role/<role>/<session> to
  # arn:aws:iam::<acct>:role/<role> so the caller grant below works whether
  # Terraform is applied by an IAM user or an assumed role (federated SSO,
  # OIDC-federated CI, etc.) — see docs/runbooks/eks-access.md.
  caller_principal_arn = replace(
    data.aws_caller_identity.current.arn,
    "/^arn:aws:sts::(\\d+):assumed-role\\/([^/]+)\\/.*$/",
    "arn:aws:iam::$1:role/$2"
  )
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Cluster IAM role (PETPLAT-12)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# KMS key for EKS secrets envelope encryption AND the cluster log group below
#
# Without the encryption_config use, Kubernetes Secrets are stored in etcd
# with no application-layer encryption (CIS EKS Benchmark / checkov
# CKV_AWS_58). An explicit key policy is required here — not optional: the
# CloudWatch Logs service does not get access to a customer-managed key from
# the AWS-default policy alone, so aws_cloudwatch_log_group.cluster below
# fails to create against this key without the second statement. (The first
# statement is the same account-root grant AWS's default policy would apply
# anyway; checkov's CKV_AWS_109/111/356 flag its wildcard actions/resource,
# which is an accepted, unavoidable trade-off for a key with any explicit
# policy at all.)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "eks_secrets_kms" {
  statement {
    sid    = "EnableAccountRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsToUseKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${local.cluster_name}/cluster"]
    }
  }
}

resource "aws_kms_key" "eks_secrets" {
  description         = "EKS secrets envelope encryption for ${local.cluster_name}"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.eks_secrets_kms.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-secrets-kms"
  })
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${local.name_prefix}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# ---------------------------------------------------------------------------
# Control plane log group — created explicitly (rather than left to EKS to
# create implicitly) so retention and encryption are managed, not left at
# the "never expire, default encryption" fallback.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
  kms_key_id        = aws_kms_key.eks_secrets.arn

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster-logs"
  })
}

# ---------------------------------------------------------------------------
# EKS cluster (PETPLAT-12)
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_sg_id]
    endpoint_private_access = false
    endpoint_public_access  = true
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # Access is managed explicitly below (PETPLAT-14) rather than via the
    # implicit creator bootstrap, so grants stay auditable in Terraform.
    bootstrap_cluster_creator_admin_permissions = false
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
    resources = ["secrets"]
  }

  # Per docs/technical-spec.md#eks-cluster (api, audit, authenticator only).
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = merge(var.tags, {
    Name = local.cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ---------------------------------------------------------------------------
# OIDC provider for IRSA (PETPLAT-12)
# ---------------------------------------------------------------------------

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-oidc"
  })
}

# ---------------------------------------------------------------------------
# Node IAM role (PETPLAT-13)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ---------------------------------------------------------------------------
# Managed node group (PETPLAT-13)
#
# A launch template attaches the vpc module's dedicated node security group
# (managed node groups otherwise only get the EKS-auto-created cluster SG).
# instance_types and disk size stay off the launch template: AWS requires
# disk_size to be unset here when a launch template is used, and keeping
# instance_types on the node group (rather than the template) allows mixed
# instance type lists.
# ---------------------------------------------------------------------------

resource "aws_launch_template" "node" {
  name_prefix            = "${local.name_prefix}-node-"
  vpc_security_group_ids = [var.node_sg_id]

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Require IMDSv2 — CIS EKS Benchmark 3.1.1 / prevents SSRF-to-credential-theft.
  # hop_limit = 1 keeps IMDS reachable only from the host network namespace
  # (kubelet, kube-proxy, vpc-cni) — application pods have no legitimate need
  # for the node role's credentials since AWS access is via IRSA, and a
  # higher hop limit would let a compromised pod reach IMDS too.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.tags, {
      Name = "${local.name_prefix}-node"
    })
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-node-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.node_instance_types
  ami_type       = var.node_ami_type
  capacity_type  = var.node_capacity_type

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = local.node_labels

  dynamic "taint" {
    for_each = var.node_taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nodes"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}

# ---------------------------------------------------------------------------
# kubectl access (PETPLAT-14)
#
# Grants the IAM principal running Terraform cluster-admin access via an EKS
# access entry (authentication_mode = API_AND_CONFIG_MAP on the cluster
# supports both this and the legacy aws-auth ConfigMap). To add another user
# or role, add an entry to additional_access_entries — see
# docs/runbooks/eks-access.md.
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "caller" {
  count = var.grant_caller_cluster_admin ? 1 : 0

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = local.caller_principal_arn
}

resource "aws_eks_access_policy_association" "caller_admin" {
  count = var.grant_caller_cluster_admin ? 1 : 0

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = local.caller_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.caller]
}

resource "aws_eks_access_entry" "additional" {
  for_each = { for entry in var.additional_access_entries : entry.principal_arn => entry }

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  kubernetes_groups = each.value.kubernetes_groups
}

resource "aws_eks_access_policy_association" "additional" {
  for_each = { for entry in var.additional_access_entries : entry.principal_arn => entry }

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  # Scoped to specific namespaces when given; cluster-wide otherwise. Default
  # policy_arn is the read-only AmazonEKSViewPolicy (see variables.tf) so an
  # entry added without a namespace list still isn't cluster-admin by default.
  access_scope {
    type       = length(each.value.namespaces) > 0 ? "namespace" : "cluster"
    namespaces = each.value.namespaces
  }

  depends_on = [aws_eks_access_entry.additional]
}

# ---------------------------------------------------------------------------
# EBS CSI Driver IRSA role (PETPLAT-84)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_id}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_id}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ebs-csi-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ---------------------------------------------------------------------------
# Managed add-ons (PETPLAT-84)
#
# Versions resolve via aws_eks_addon_version (most recent build compatible
# with cluster_version) unless pinned explicitly through the *_addon_version
# variables. Either way the resource's addon_version is always a concrete
# version string — never the literal "latest". See
# docs/runbooks/eks-access.md for the upgrade procedure.
# ---------------------------------------------------------------------------

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = coalesce(var.coredns_addon_version, data.aws_eks_addon_version.coredns.version)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-coredns"
  })

  # CoreDNS pods need schedulable nodes.
  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = coalesce(var.kube_proxy_addon_version, data.aws_eks_addon_version.kube_proxy.version)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-kube-proxy"
  })
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = coalesce(var.vpc_cni_addon_version, data.aws_eks_addon_version.vpc_cni.version)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-cni"
  })
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = coalesce(var.ebs_csi_addon_version, data.aws_eks_addon_version.ebs_csi.version)
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ebs-csi"
  })

  # EBS CSI controller pods need schedulable nodes.
  depends_on = [aws_eks_node_group.this]
}
