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
  name_prefix = "${var.project}-${var.environment}"
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
  name              = "/aws/rds/instance/${local.name_prefix}-mysql/error"
  retention_in_days = var.log_retention_days

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

  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false

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
