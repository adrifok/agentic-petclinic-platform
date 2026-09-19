#!/usr/bin/env bash
# Validates the generic Helm chart (helm/petclinic-service/) against every
# service x environment combination: helm lint, helm template, and
# kubectl apply --dry-run=client on the rendered output.
#
# Implements PETPLAT-110. Usage: ./scripts/validate-helm.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$REPO_ROOT/helm/petclinic-service"
VALUES_DIR="$REPO_ROOT/helm-values"
RENDER_DIR="$(mktemp -d)"
trap 'rm -rf "$RENDER_DIR"' EXIT

SERVICES=(config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server)
ENVIRONMENTS=(dev prod)

fail=0

echo "============================================"
echo "  Helm chart validation: $CHART"
echo "============================================"

echo
echo "[1/3] helm lint (chart defaults)"
if helm lint "$CHART"; then
  echo "  -> OK"
else
  echo "  -> FAILED"
  fail=1
fi

for env in "${ENVIRONMENTS[@]}"; do
  ns="petclinic-${env}"

  # prod.yaml's datasource.url is a deliberate placeholder (prod RDS doesn't
  # exist yet) that the chart refuses to render — see
  # helm/petclinic-service/templates/configmap.yaml. Override it here so
  # rendering can still be validated; this never touches the checked-in
  # file, so a real `helm install` against prod.yaml as committed still
  # fails loudly until someone fills in the real endpoint.
  extra_set=(--set image.tag=v1.0.0)
  if [ "$env" = "prod" ]; then
    extra_set+=(--set datasource.url=jdbc:mysql://ci-validation-placeholder.invalid:3306/petclinic)
  fi

  for svc in "${SERVICES[@]}"; do
    echo
    echo "[2/3] helm lint + template: $svc ($env)"
    if ! helm lint "$CHART" \
      -f "$VALUES_DIR/${svc}.yaml" \
      -f "$VALUES_DIR/${env}.yaml" \
      "${extra_set[@]}" >/tmp/helm-lint-out 2>&1; then
      echo "  -> LINT FAILED"
      cat /tmp/helm-lint-out
      fail=1
      continue
    fi

    out_file="$RENDER_DIR/${svc}-${env}.yaml"
    if ! helm template "$svc" "$CHART" \
      -n "$ns" \
      -f "$VALUES_DIR/${svc}.yaml" \
      -f "$VALUES_DIR/${env}.yaml" \
      "${extra_set[@]}" >"$out_file" 2>/tmp/helm-template-out; then
      echo "  -> TEMPLATE FAILED"
      cat /tmp/helm-template-out
      fail=1
      continue
    fi
    echo "  -> rendered $(grep -c '^kind:' "$out_file") resources"

    echo "[3/3] kubectl apply --dry-run=client: $svc ($env)"
    if kubectl apply --dry-run=client -f "$out_file" >/tmp/kubectl-dry-run-out 2>&1; then
      echo "  -> OK"
    else
      echo "  -> DRY RUN FAILED"
      cat /tmp/kubectl-dry-run-out
      fail=1
    fi
  done
done

echo
echo "============================================"
if [ "$fail" -eq 0 ]; then
  echo "  All checks passed."
else
  echo "  One or more checks FAILED — see output above."
fi
echo "============================================"

exit "$fail"
