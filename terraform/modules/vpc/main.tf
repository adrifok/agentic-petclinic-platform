# Module: vpc
# VPC, 2 public subnets across 2 AZs, Internet Gateway, single public route
# table, and baseline security groups (EKS cluster/node, RDS, ALB).
#
# All-public subnet design — no NAT Gateway, no private subnets, no VPC
# endpoints. Security groups are the perimeter. See ADR-0001 in
# docs/technical-spec.md#adr-index and docs/technical-spec.md#vpc-network-design
# / #security-groups.
#
# Implements PETPLAT-6 (VPC, subnets, IGW) and PETPLAT-8 (baseline SGs).

locals {
  name_prefix = "${var.project}-${var.environment}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Lock down the auto-created default SG so nothing can silently rely on it
# (CIS AWS Foundations 4.3/5.3). All access control goes through the
# dedicated SGs below.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-default-sg-DO-NOT-USE"
  })
}

# ---------------------------------------------------------------------------
# Public subnets (2 AZs) — host EKS nodes, RDS, and the ALB
# ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                         = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  })
}

# ---------------------------------------------------------------------------
# Internet Gateway + single public route table
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# VPC Flow Logs — the main compensating control for the all-public,
# SG-as-perimeter design (no NAT/private subnets to fall back on). Captures
# ALL (accept + reject) traffic to a KMS-encrypted CloudWatch Logs group,
# following the same explicit log-group + dedicated key pattern as the eks
# module's control-plane logs. Flagged by the security-auditor review as a
# gap not covered by ADR-0001 (which addresses subnet/NAT design only).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "flow_log_kms" {
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
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc-flow-log/${local.name_prefix}"]
    }
  }
}

resource "aws_kms_key" "flow_log" {
  description             = "VPC flow log encryption for ${local.name_prefix}"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.flow_log_kms.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-flow-log-kms"
  })
}

resource "aws_kms_alias" "flow_log" {
  name          = "alias/${local.name_prefix}-vpc-flow-log"
  target_key_id = aws_kms_key.flow_log.key_id
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc-flow-log/${local.name_prefix}"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = aws_kms_key.flow_log.arn

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-flow-log"
  })
}

data "aws_iam_policy_document" "flow_log_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_log" {
  name               = "${local.name_prefix}-vpc-flow-log-role"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-flow-log-role"
  })
}

data "aws_iam_policy_document" "flow_log_delivery" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["${aws_cloudwatch_log_group.flow_log.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_log_delivery" {
  name   = "${local.name_prefix}-vpc-flow-log-delivery"
  role   = aws_iam_role.flow_log.id
  policy = data.aws_iam_policy_document.flow_log_delivery.json
}

resource "aws_flow_log" "this" {
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_log.arn
  iam_role_arn         = aws_iam_role.flow_log.arn
  vpc_id               = aws_vpc.this.id
  traffic_type         = var.flow_log_traffic_type

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-flow-log"
  })
}

# ---------------------------------------------------------------------------
# Baseline security groups (PETPLAT-8)
#
# Each SG is declared bare (no inline ingress/egress) and rules are attached
# as separate aws_vpc_security_group_{ingress,egress}_rule resources. This
# avoids the create-time cycle from the EKS cluster SG <-> node SG
# cross-references and keeps each rule independently auditable.
# ---------------------------------------------------------------------------

# --- EKS cluster (control plane) SG ---

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS control plane security group"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "eks_cluster_from_node_443" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "API server access from EKS nodes"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "eks_cluster_all_egress" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = var.tags
}

# --- EKS node (worker) SG ---

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker node security group"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-node-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_from_cluster_all" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "All traffic from EKS control plane"
  referenced_security_group_id = aws_security_group.eks_cluster.id
  ip_protocol                  = "-1"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_self" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Inter-node communication"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "-1"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_from_cluster_kubelet" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Kubelet API from EKS control plane"
  referenced_security_group_id = aws_security_group.eks_cluster.id
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_from_alb_nodeport" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "NodePort services from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_from_alb_healthcheck" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "API Gateway pod traffic/health checks from ALB (target-type: ip)"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "eks_node_all_egress" {
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound (no NAT - nodes reach ECR/S3/Secrets Manager directly via IGW)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = var.tags
}

# --- RDS SG ---

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL security group - allows 3306 from EKS nodes only"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_node_mysql" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from EKS nodes only"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306

  tags = var.tags
}

# No egress rule: RDS does not initiate outbound connections and is fully
# locked down by default once inline egress is omitted from aws_security_group.

# --- ALB SG ---

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group - public HTTP/HTTPS ingress"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "alb_to_node_nodeport" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To EKS node target groups"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "alb_to_node_healthcheck" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Health checks to EKS nodes"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080

  tags = var.tags
}
