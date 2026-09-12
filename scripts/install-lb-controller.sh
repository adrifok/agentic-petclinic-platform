#!/usr/bin/env bash
#
# install-lb-controller.sh — install the AWS Load Balancer Controller on EKS.
#
# Installs a pinned CRDs release, adds the eks Helm repo, and
# helm-upgrade-installs a pinned aws-load-balancer-controller chart version
# into kube-system using IRSA (the petclinic-{env}-lb-controller-role
# Terraform creates — PETPLAT-29). Then applies the alb IngressClass.
# Idempotent — safe to re-run. See CHART_VERSION/CRDS_URL below to bump.
#
# Usage:
#   ./scripts/install-lb-controller.sh <environment> [--region eu-central-1] [--role-arn <arn>]
#
# Examples:
#   ./scripts/install-lb-controller.sh dev
#   ./scripts/install-lb-controller.sh prod --region eu-central-1
#
# LB_CONTROLLER_ROLE_ARN can be set in the environment instead of --role-arn;
# otherwise this script reads it from `terraform output` in
# terraform/environments/<environment>/ (requires that stack to be applied).
#
# See docs/technical-spec.md#dns-and-ingress and #irsa-roles.

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-eu-central-1}"
ROLE_ARN="${LB_CONTROLLER_ROLE_ARN:-}"
ENV=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HELM_REPO_URL="https://aws.github.io/eks-charts"

# Pinned, not "master"/"latest" — both must be bumped together (they're the
# same upstream release; check https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases
# for the controller version, then the matching eks-charts repo tag in
# stable/aws-load-balancer-controller/Chart.yaml on that tag).
CHART_VERSION="3.5.0"
CRDS_URL="https://raw.githubusercontent.com/aws/eks-charts/v0.0.244/stable/aws-load-balancer-controller/crds/crds.yaml"

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
echo "  Installing AWS Load Balancer Controller"
echo "  Environment: ${ENV}"
echo "  Cluster:     ${CLUSTER_NAME}"
echo "  Region:      ${REGION}"
echo "============================================"
echo ""

# --- Resolve IRSA role ARN ---
if [[ -z "${ROLE_ARN}" ]]; then
  command -v terraform >/dev/null 2>&1 || {
    echo "Error: no --role-arn given, LB_CONTROLLER_ROLE_ARN not set, and terraform not found to look it up." >&2
    exit 1
  }
  echo "[1/6] Reading lb_controller_role_arn from terraform output (${TF_DIR})"
  ROLE_ARN="$(terraform -chdir="${TF_DIR}" output -raw lb_controller_role_arn 2>/dev/null || true)"
  if [[ -z "${ROLE_ARN}" ]]; then
    echo "Error: could not read lb_controller_role_arn. Apply terraform/environments/${ENV} first," >&2
    echo "       or pass --role-arn <arn> / set LB_CONTROLLER_ROLE_ARN." >&2
    exit 1
  fi
else
  echo "[1/6] Using provided IRSA role ARN"
fi
echo "  -> ${ROLE_ARN}"
echo ""

# --- kubeconfig ---
echo "[2/6] Updating kubeconfig for ${CLUSTER_NAME}"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}" >/dev/null
echo "  -> done"
echo ""

# --- Helm repo ---
echo "[3/6] Adding/updating the eks Helm repo (${HELM_REPO_URL})"
helm repo add eks "${HELM_REPO_URL}" --force-update >/dev/null
helm repo update eks >/dev/null
echo "  -> done"
echo ""

# --- CRDs ---
# helm install applies bundled CRDs automatically, but helm upgrade does not
# (see upstream install docs) — applying explicitly covers both paths and is
# idempotent either way.
echo "[4/6] Applying CRDs"
kubectl apply -f "${CRDS_URL}" >/dev/null
echo "  -> done"
echo ""

# --- Helm install/upgrade ---
echo "[5/6] helm upgrade --install aws-load-balancer-controller ${CHART_VERSION} (namespace: kube-system)"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version "${CHART_VERSION}" \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set region="${REGION}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ROLE_ARN}" \
  --wait --timeout 5m

echo ""
echo "  Waiting for rollout..."
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s
echo ""

# --- IngressClass ---
echo "[6/6] Applying IngressClass (alb)"
kubectl apply -f "${REPO_ROOT}/k8s/base/ingress/ingressclass.yaml"
echo ""

echo "============================================"
echo "  Done."
echo ""
echo "  Verify:"
echo "    kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
echo "    kubectl get ingressclass alb"
echo "============================================"
