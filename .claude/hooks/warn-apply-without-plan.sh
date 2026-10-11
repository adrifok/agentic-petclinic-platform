#!/usr/bin/env bash
# Hook: warn-apply-without-plan.sh (PreToolUse on Bash)
# Purpose: Asks for confirmation when 'terraform apply' runs without a saved plan file.
# Why: Running 'terraform apply' without a plan can make unexpected changes.
#      The safe workflow is: plan -out plan.out -> review -> apply plan.out.
# How: Returns permissionDecision "ask" as JSON on stdout, so Claude Code prompts
#      the user. (A bare exit 1 is a non-blocking error and does NOT prompt.)

set -euo pipefail

# shellcheck source=lib/segments.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/segments.sh"
require_jq warn-apply-without-plan.sh

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT")

if [ -z "$COMMAND" ]; then
  exit 0
fi

ask() {
  jq -n --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

TF='\b(terraform|terragrunt|tofu)\b'

while IFS= read -r seg; do
  is_text_only "$seg" && continue
  if grep -qE "${TF}.*\sapply\b" <<<"$seg"; then
    # Saved plan file provided — the safe workflow
    if grep -qE '\bapply\b.*\.(out|tfplan)(\s|$)' <<<"$seg"; then
      continue
    fi
    if grep -qE '\-auto-approve' <<<"$seg"; then
      ask "terraform apply -auto-approve without a saved plan: skips confirmation and reviews nothing. Use: terraform plan -out plan.out, review, terraform apply plan.out."
    fi
    ask "terraform apply without a saved plan: Terraform re-plans at apply time and the changes may differ from what was reviewed. Use: terraform plan -out plan.out, review, terraform apply plan.out."
  fi
done < <(segments "$COMMAND")

exit 0
