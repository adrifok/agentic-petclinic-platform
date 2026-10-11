#!/usr/bin/env bash
# Hook: block-destroy.sh (PreToolUse on Bash)
# Purpose: HARD BLOCK on irreversible destroy operations run through Claude Code.
# Why: Destroy is irreversible. In a shared AWS account, accidental destroy
#      can delete VPCs, EKS clusters, RDS databases — causing hours of downtime.
# Covers:
#   - terraform/terragrunt/tofu destroy with any flags (-chdir=, --terragrunt-working-dir X),
#     run-all / run --all destroy, apply -destroy, applying a "*destroy*.out|.tfplan" plan
#   - kubectl delete touching petclinic-prod (namespace, context or name), -A,
#     namespaces by --all/selector, --all without -n, prod ArgoCD Application CRs/manifests
#   - helm uninstall/delete in petclinic-prod
#   - argocd app/appset delete of *-prod apps
#   - aws CLI delete-*/terminate-*/deregister-* referencing petclinic-prod
# Not checked: heredoc bodies, and text-only commands (git/gh/echo/grep/cat ...)
#   so commit messages and docs searches mentioning these words are not blocked.
# Limits: string matching only. A saved destroy plan with a neutral filename, or
#   commands hidden behind variables, are not detected — permissions.deny in
#   settings.json is the second layer.
# How: exit 2 = deny; the reason on stderr is shown to Claude.

set -euo pipefail

# shellcheck source=lib/segments.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/segments.sh"
require_jq block-destroy.sh

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT")

if [ -z "$COMMAND" ]; then
  exit 0
fi

block() {
  {
    echo "BLOCKED: $1"
    echo ""
    echo "Irreversible operations must be run by a human, directly in a terminal:"
    echo "  1. Review first (terraform plan -destroy, kubectl get ..., argocd app get ...)"
    echo "  2. Run the command yourself, outside Claude Code"
  } >&2
  exit 2
}

TF='\b(terraform|terragrunt|tofu)\b'

while IFS= read -r seg; do
  [ -z "${seg// /}" ] && continue
  is_text_only "$seg" && continue

  # --- Terraform family ---
  # "\sdestroy(\s|$|quote)" keeps "plan -destroy" and "-out destroy.out" allowed;
  # the quote case catches bash -c "terraform destroy"
  if grep -qE "${TF}.*\s(destroy|destroy-all)(\s|$|[\"'])" <<<"$seg"; then
    block "'terraform/terragrunt destroy' (any flags or run-all form) is not allowed via Claude Code."
  fi
  if grep -qE "${TF}.*\sapply\b.*\s-destroy(\s|$|[\"'])" <<<"$seg"; then
    block "'apply -destroy' is equivalent to 'terraform destroy'."
  fi
  if grep -qE "${TF}.*\sapply\b.*destroy[^[:space:]]*\.(out|tfplan)(\s|$|[\"'])" <<<"$seg"; then
    block "Applying a saved destroy plan is equivalent to 'terraform destroy'."
  fi

  # --- kubectl ---
  if grep -qE '\bkubectl\b.*\sdelete\b' <<<"$seg"; then
    if grep -qE 'petclinic-prod' <<<"$seg"; then
      block "'kubectl delete' touching petclinic-prod (namespace, context or resource) is not allowed via Claude Code."
    fi
    if grep -qE '(\s-A\b|--all-namespaces)' <<<"$seg"; then
      block "'kubectl delete' across all namespaces is not allowed via Claude Code."
    fi
    if grep -qE '\sdelete\s+(ns|namespaces?)\b' <<<"$seg" && grep -qE '(\s--all\b|\s-l\b|--selector)' <<<"$seg"; then
      block "Bulk namespace deletion is not allowed via Claude Code."
    fi
    if grep -qE '\s--all\b' <<<"$seg" && ! grep -qE '(\s-n\b|\s-n[a-z]|--namespace)' <<<"$seg"; then
      block "'kubectl delete --all' without an explicit -n targets the context default namespace (could be prod)."
    fi
    if grep -qE 'applications/prod' <<<"$seg"; then
      block "Deleting prod ArgoCD Application manifests is not allowed via Claude Code."
    fi
    if grep -qE '\sdelete\s+(-[^[:space:]]+\s+)*(applications?|appprojects?|applicationsets?|apps?)(\.argoproj\.io)?(\s|/)' <<<"$seg" &&
       grep -qE '[a-z0-9]-prod\b' <<<"$seg"; then
      block "Deleting a prod ArgoCD Application CR cascades to its workloads."
    fi
  fi

  # --- helm ---
  if grep -qE '\bhelm\b.*\s(uninstall|delete|del|un)\b' <<<"$seg" && grep -qE 'petclinic-prod' <<<"$seg"; then
    block "'helm uninstall' in petclinic-prod is not allowed via Claude Code."
  fi

  # --- argocd ---
  if grep -qE '\bargocd\b.*\s(app|appset)\s+delete\b' <<<"$seg" && grep -qE '(-prod\b|petclinic-prod)' <<<"$seg"; then
    block "'argocd app delete' of a prod Application is not allowed via Claude Code."
  fi

  # --- aws CLI ---
  if grep -qE '\baws\b.*\s(delete|terminate|deregister)-[a-z-]+' <<<"$seg" && grep -qE 'petclinic-prod' <<<"$seg"; then
    block "AWS CLI delete/terminate on petclinic-prod resources is not allowed via Claude Code."
  fi
done < <(segments "$COMMAND")

exit 0
