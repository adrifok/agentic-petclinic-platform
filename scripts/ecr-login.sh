#!/usr/bin/env bash
#
# ecr-login.sh — authenticate Docker to the private ECR registry.
#
# Usage:
#   ./scripts/ecr-login.sh [--region eu-central-1]
#
# See docs/technical-spec.md#ecr-container-registry and PETPLAT-21.

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-eu-central-1}"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  exit 1
}

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
      usage
      ;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "aws CLI not found in PATH" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH" >&2; exit 1; }

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Logging in to ${REGISTRY}..."
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"
