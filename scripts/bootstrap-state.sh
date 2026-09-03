#!/usr/bin/env bash
# bootstrap-state.sh — one-time provisioning of the Terraform remote state
# backend: an S3 bucket (versioned, encrypted, public access blocked) and a
# DynamoDB lock table. Run once before `terraform init` in any environment.
# Idempotent: safe to re-run, existing resources are left untouched.
#
# Usage: scripts/bootstrap-state.sh [--region eu-central-1]
#
# See docs/technical-spec.md#terraform-state-backend and PETPLAT-2.

set -euo pipefail

REGION="eu-central-1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--region <aws-region>]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "aws CLI not found in PATH" >&2; exit 1; }

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="petclinic-terraform-state-${ACCOUNT_ID}"
TABLE="petclinic-terraform-locks"

echo "Region:  ${REGION}"
echo "Bucket:  ${BUCKET}"
echo "Table:   ${TABLE}"
echo

# --- S3 bucket -------------------------------------------------------------

if aws s3api head-bucket --bucket "${BUCKET}" --region "${REGION}" 2>/dev/null; then
  echo "S3 bucket ${BUCKET} already exists — skipping creation."
else
  echo "Creating S3 bucket ${BUCKET}..."
  # us-east-1 rejects a LocationConstraint; every other region requires one.
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
fi

echo "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

echo "Enabling default encryption (AES256)..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

echo "Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# --- DynamoDB lock table -----------------------------------------------------

if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo "DynamoDB table ${TABLE} already exists — skipping creation."
else
  echo "Creating DynamoDB table ${TABLE}..."
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" \
    --tags Key=Project,Value=petclinic Key=ManagedBy,Value=bootstrap-script >/dev/null

  echo "Waiting for table to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "${TABLE}" --region "${REGION}"
fi

cat <<EOF

Done. Point each environment's backend at this bucket, e.g.:

  cd terraform/environments/dev
  terraform init -backend-config="bucket=${BUCKET}"

or copy backend.hcl.example to backend.hcl and run:

  terraform init -backend-config=backend.hcl
EOF
