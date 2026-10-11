#!/usr/bin/env bash
# Hook: block-dangerous-rm.sh (PreToolUse on Bash)
# Purpose: Blocks recursive 'rm' on critical infrastructure directories.
# Why: Accidentally deleting terraform/, k8s/, or .github/ means
#      losing all infrastructure code. Git can recover it, but the blast radius
#      of an accidental 'rm -rf terraform/' is too high to leave unguarded.
# How: For each command segment (heredoc bodies ignored), checks for a recursive rm
#      targeting a protected directory. Plain 'rm -f <file>' is allowed so single
#      files (e.g. stale plan.out) can be removed. Exits 2 to deny execution.

set -euo pipefail

# shellcheck source=lib/segments.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/segments.sh"
require_jq block-dangerous-rm.sh

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Protected directories — these contain all our infrastructure code
PROTECTED_DIRS="terraform k8s helm helm-values .github docs scripts .claude"

while IFS= read -r seg; do
  # Recursive rm: -r, -R, -rf, -fr, -r -f, --recursive (long flags may precede it)
  grep -qE '\brm\s+(--?[a-zA-Z-]+\s+)*(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)\b' <<<"$seg" || continue
  for dir in $PROTECTED_DIRS; do
    # Match: rm -rf terraform, ./terraform, terraform/, "terraform", etc.
    if grep -qE "\brm\s+.*(\s|/)[\"']?\.?/?${dir}(/|\s|$|[\"'])" <<<"$seg"; then
      {
        echo "BLOCKED: Cannot 'rm -rf' the '${dir}/' directory."
        echo ""
        echo "This directory contains critical infrastructure code."
        echo "If you need to remove specific files, delete them individually."
        echo "If you need to reset the directory, use 'git checkout -- ${dir}/'."
      } >&2
      exit 2
    fi
  done
done < <(segments "$COMMAND")

exit 0
