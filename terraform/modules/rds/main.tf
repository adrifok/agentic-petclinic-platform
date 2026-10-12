# Module: rds
# RDS MySQL instance shared by customers/visits/vets services, plus generated
# master credentials stored in Secrets Manager.
#
# Implements PETPLAT-22 (RDS instance) and PETPLAT-23 (Secrets Manager
# credentials). See docs/technical-spec.md#rds-database and
# docs/technical-spec.md#secrets-management. Schema initialization strategy
# (PETPLAT-24) is documented in docs/runbooks/rds-database-init.md — this
# module only provisions the empty `petclinic` database; Spring Boot
# auto-initializes the schema on first service startup.

locals {
  name_prefix    = "${var.project}-${var.environment}"
  error_log_name = "/aws/rds/instance/${local.name_prefix}-mysql/error"
  kms_key_arn    = var.create_kms_key ? aws_kms_key.rds[0].arn : null
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Customer-managed KMS key (PET-8) for RDS storage and the error log group.
# Must exist at instance creation: changing kms_key_id later forces RDS
# replacement.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "rds_kms" {
  count = var.create_kms_key ? 1 : 0

  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogsErrorLogGroup"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.error_log_name}"]
    }
  }
}

resource "aws_kms_key" "rds" {
  count = var.create_kms_key ? 1 : 0

  description             = "${local.name_prefix} RDS storage and log encryption"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.rds_kms[0].json

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-kms"
  })
}

resource "aws_kms_alias" "rds" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${local.name_prefix}-rds"
  target_key_id = aws_kms_key.rds[0].key_id
}

# ---------------------------------------------------------------------------
# Master credentials (PETPLAT-23) — generated, never accepted as a variable.
# Terraform propagates the `sensitive` mark from random_password.result
# through jsonencode() to secret_string, so the password is redacted from
# plan/apply CLI output and `terraform show`.
# ---------------------------------------------------------------------------

resource "random_password" "master" {
  length  = 20
  special = true
  # Excludes /, @, ", and space — all disallowed in RDS MySQL passwords.
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "${var.project}/${var.environment}/rds-credentials"
  description             = "RDS master credentials for ${local.name_prefix}-mysql."
  recovery_window_in_days = var.secret_recovery_window_days

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
  })
}

# ---------------------------------------------------------------------------
# DB subnet group + parameter group (utf8mb4 — PETPLAT-22)
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

resource "aws_db_parameter_group" "this" {
  name   = "${local.name_prefix}-mysql8"
  family = "mysql8.0"

  # Both are static parameters in RDS MySQL — take effect after a reboot,
  # which happens automatically since this is the initial parameter group
  # attached at creation (no running instance to reboot yet).
  parameter {
    name         = "character_set_server"
    value        = "utf8mb4"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "collation_server"
    value        = "utf8mb4_unicode_ci"
    apply_method = "pending-reboot"
  }

  # Reject non-TLS connections (PET-8). Dynamic parameter, no reboot.
  parameter {
    name  = "require_secure_transport"
    value = "1"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-mysql8"
  })
}

# ---------------------------------------------------------------------------
# Error log export to CloudWatch — declared explicitly (same reasoning as
# the eks module's cluster log group) so Terraform owns the retention
# setting instead of RDS auto-creating the group with "Never expire" on
# first log write, and instead of a delete-then-recreate race like the one
# hit on the EKS control-plane log group. general/slowquery/audit exports
# are skipped: they need extra parameter-group flags (general_log,
# slow_query_log, the MariaDB audit plugin) that are out of this module's
# scope; error log needs no such flag and already covers auth/connection
# failures.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "rds_error" {
  name              = local.error_log_name
  retention_in_days = var.log_retention_days
  kms_key_id        = local.kms_key_arn

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-error-logs"
  })
}

# ---------------------------------------------------------------------------
# RDS MySQL instance — single shared `petclinic` database for
# customers/visits/vets services (PETPLAT-24). publicly_accessible is false
# so the instance gets no public IP even though it sits in a public subnet;
# per ADR-0001 the security group (3306 from EKS node SG only) is the access
# boundary, not subnet placement.
# ---------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier     = "${local.name_prefix}-mysql"
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true
  kms_key_id            = local.kms_key_arn

  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  # Operator/bootstrap access only; apps keep password auth (Connector/J
  # would need the AWS JDBC wrapper for IAM tokens).
  iam_database_authentication_enabled = true

  multi_az                   = var.multi_az
  backup_retention_period    = var.backup_retention_period
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-mysql-final-snapshot"
  deletion_protection       = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["error"]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-mysql"
  })

  depends_on = [aws_cloudwatch_log_group.rds_error]
}

# ---------------------------------------------------------------------------
# Per-service DB credentials (PET-8). Terraform only generates and stores
# them; the MySQL users and grants are created by the in-cluster bootstrap
# job (PET-14), since RDS is not reachable from outside the VPC.
# ---------------------------------------------------------------------------

resource "random_password" "app" {
  for_each = toset(var.app_db_users)

  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "app" {
  for_each = toset(var.app_db_users)

  name                    = "${var.project}/${var.environment}/db-${each.key}"
  description             = "MySQL credentials for ${each.key}-service on ${local.name_prefix}-mysql."
  recovery_window_in_days = var.secret_recovery_window_days

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-db-${each.key}"
  })
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each = toset(var.app_db_users)

  secret_id = aws_secretsmanager_secret.app[each.key].id
  secret_string = jsonencode({
    username = each.key
    password = random_password.app[each.key].result
  })
}
