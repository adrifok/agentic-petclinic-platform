#!/usr/bin/env bash
#
# install-external-secrets.sh — install External Secrets Operator (ESO) on EKS.
#
# Adds the external-secrets Helm repo and helm-upgrade-installs a pinned
# external-secrets chart version into the external-secrets namespace, using
# IRSA (the petclinic-{env}-eso-role Terraform creates — PETPLAT-37). The
# chart manages its own CRDs as regular templates (unlike the aws-load-balancer-
# controller chart), so a plain helm upgrade keeps them current — no separate
# CRD apply step is needed. Then applies the ClusterSecretStore.
# Idempotent — safe to re-run. See CHART_VERSION below to bump.
#
# Usage:
#   ./scripts/install-external-secrets.sh <environment> [--region eu-central-1] [--role-arn <arn>]
#
# Examples:
#   ./scripts/install-external-secrets.sh dev
#   ./scripts/install-external-secrets.sh prod --region eu-central-1
#
# ESO_ROLE_ARN can be set in the environment instead of --role-arn; otherwise
# this script reads it from `terraform output` in
# terraform/environments/<environment>/ (requires that stack to be applied).
#
# After this script, apply the ExternalSecret CRs for your services:
#   dev:  kubectl apply -f k8s/base/external-secrets/rds-credentials.yaml
#         kubectl apply -f k8s/base/external-secrets/openai-api-key.yaml
#   prod: kubectl apply -f k8s/base/external-secrets/rds-credentials-prod.yaml
#         kubectl apply -f k8s/base/external-secrets/openai-api-key-prod.yaml
#
# See docs/technical-spec.md#secrets-management and #irsa-roles.

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-eu-central-1}"
ROLE_ARN="${ESO_ROLE_ARN:-}"
ENV=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HELM_REPO_URL="https://charts.external-secrets.io"

# Pinned, not "latest" — check https://github.com/external-secrets/external-secrets/releases
# for the current chart version before bumping (chart version tracks the app
# version 1:1 for this project).
CHART_VERSION="2.10.0"

usage() {
  echo "Usage: $0 <environment> [--region <aws-region>] [--role-arn <arn>]"
  echo "  environment: dev | prod"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi
ENV="$1"
shift
if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "Error: environment must be 'dev' or 'prod'" >&2
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    --role-arn)
      ROLE_ARN="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

for cmd in aws kubectl helm; do
  command -v "${cmd}" >/dev/null 2>&1 || { echo "${cmd} not found in PATH" >&2; exit 1; }
done

CLUSTER_NAME="petclinic-${ENV}"
TF_DIR="${REPO_ROOT}/terraform/environments/${ENV}"

echo "============================================"
echo "  Installing External Secrets Operator"
echo "  Environment: ${ENV}"
echo "  Cluster:     ${CLUSTER_NAME}"
echo "  Region:      ${REGION}"
echo "============================================"
echo ""

# --- Resolve IRSA role ARN ---
if [[ -z "${ROLE_ARN}" ]]; then
  command -v terraform >/dev/null 2>&1 || {
    echo "Error: no --role-arn given, ESO_ROLE_ARN not set, and terraform not found to look it up." >&2
    exit 1
  }
  echo "[1/5] Reading eso_role_arn from terraform output (${TF_DIR})"
  ROLE_ARN="$(terraform -chdir="${TF_DIR}" output -raw eso_role_arn 2>/dev/null || true)"
  if [[ -z "${ROLE_ARN}" ]]; then
    echo "Error: could not read eso_role_arn. Apply terraform/environments/${ENV} first," >&2
    echo "       or pass --role-arn <arn> / set ESO_ROLE_ARN." >&2
    exit 1
  fi
else
  echo "[1/5] Using provided IRSA role ARN"
fi
echo "  -> ${ROLE_ARN}"
echo ""

# --- kubeconfig ---
echo "[2/5] Updating kubeconfig for ${CLUSTER_NAME}"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}" >/dev/null
echo "  -> done"
echo ""

# --- Helm repo ---
echo "[3/5] Adding/updating the external-secrets Helm repo (${HELM_REPO_URL})"
helm repo add external-secrets "${HELM_REPO_URL}" --force-update >/dev/null
helm repo update external-secrets >/dev/null
echo "  -> done"
echo ""

# --- Helm install/upgrade ---
echo "[4/5] helm upgrade --install external-secrets ${CHART_VERSION} (namespace: external-secrets)"
helm upgrade --install external-secrets external-secrets/external-secrets \
  --version "${CHART_VERSION}" \
  --namespace external-secrets \
  --create-namespace \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-secrets-sa \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ROLE_ARN}" \
  --wait --timeout 5m

echo ""
echo "  Waiting for rollout..."
kubectl rollout status deployment/external-secrets -n external-secrets --timeout=120s
echo ""

# --- ClusterSecretStore ---
echo "[5/5] Applying ClusterSecretStore (aws-secrets-manager)"
kubectl apply -f "${REPO_ROOT}/k8s/base/external-secrets/cluster-secret-store.yaml"
echo ""

echo "============================================"
echo "  Done."
echo ""
echo "  Verify:"
echo "    kubectl get pods -n external-secrets"
echo "    kubectl get clustersecretstore aws-secrets-manager"
echo ""
echo "  Next: apply the ExternalSecret CRs for ${ENV}, e.g."
if [[ "${ENV}" == "dev" ]]; then
  echo "    kubectl apply -f k8s/base/external-secrets/rds-credentials.yaml"
  echo "    kubectl apply -f k8s/base/external-secrets/openai-api-key.yaml"
else
  echo "    kubectl apply -f k8s/base/external-secrets/rds-credentials-prod.yaml"
  echo "    kubectl apply -f k8s/base/external-secrets/openai-api-key-prod.yaml"
fi
echo "============================================"
