#!/usr/bin/env bash
# Hook: block-secret-commit.sh (PreToolUse on Bash)
# Purpose: Blocks git add/commit of files that may contain secrets.
# Why: Committing .env files, *.tfvars, credentials, or key files to git is a
#      security incident. Once pushed, secrets are in git history forever
#      (even after deletion). Prevention is much cheaper than rotation.
# How: For each git segment (heredoc bodies and commit message text removed), blocks
#      bulk staging (., *, :/, -A, --all), force-adding ignored files (-f),
#      commit -a, and secret-like filenames. exit 2 = deny; reason on stderr.

set -euo pipefail

# shellcheck source=lib/segments.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/segments.sh"
require_jq block-secret-commit.sh

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT")

if [ -z "$COMMAND" ]; then
  exit 0
fi

block() {
  {
    echo "BLOCKED: $1"
    echo ""
    echo "Add files explicitly by name, e.g.:"
    echo "  git add terraform/modules/vpc/main.tf terraform/modules/vpc/variables.tf"
    echo "Secrets belong in AWS Secrets Manager; use *.example files with placeholders."
    echo "If this is a false positive, run the git command directly in your terminal."
  } >&2
  exit 2
}

# git with optional global options (-C dir, -c k=v, --no-pager, ...)
GIT='\bgit(\s+(-C|-c)\s+[^[:space:]]+|\s+--?[a-z-]+(=[^[:space:]]+)?)*'

SECRET_FILE_PATTERNS=(
  '\.env($|\s|/)'           # .env files (but not .envrc)
  '\.env\.(local|dev|prod|production|development|staging|test)($|\s)'  # .env.<env>; .env.example stays allowed
  '\.tfvars($|\s)'          # terraform.tfvars (actual secrets)
  '\.tfstate'               # state holds plaintext secrets
  '\.(out|tfplan)($|\s)'    # saved plans hold plaintext secrets
  '\.pem($|\s)'             # PEM certificates/keys
  '\.key($|\s)'             # Private key files
  '\.p12($|\s)'             # PKCS12 keystores
  '\.pfx($|\s)'             # PFX certificates
  'kubeconfig'              # Kubernetes config with cluster creds
  'aws-credentials'         # AWS credential files
  'credentials\.json'       # Service account credentials
  'credentials\.yaml'       # Credential files
)

while IFS= read -r seg; do
  [ "$(first_word "$seg")" = "git" ] || continue

  # Drop message arguments (-m/--message, quoted or bare; an unterminated quote
  # means a multi-line message, so drop to end of line) before any check.
  args=$(sed -E \
    -e "s/\s(-m|--message)(\s+|=)('[^']*'|\"[^\"]*\"|[^[:space:]'\"]+)//g" \
    -e "s/\s(-m|--message)(\s+|=)['\"].*$//" <<<"$seg")

  if grep -qE "${GIT}\s+add\b" <<<"$args"; then
    if grep -qE "${GIT}\s+add\b.*\s(\.|\./|\*|:/|-A|--all|-[a-zA-Z]*A[a-zA-Z]*)(\s|$)" <<<"$args"; then
      block "Bulk 'git add' (., *, :/, -A, --all) can stage secret files."
    fi
    # Force-add bypasses .gitignore, which is the main secret guard
    if grep -qE "${GIT}\s+add\b.*\s(-f|--force|-[a-zA-Z]*f[a-zA-Z]*)(\s|$)" <<<"$args"; then
      block "'git add -f' bypasses .gitignore (which protects *.tfvars, .env, *.pem, plan files)."
    fi
  fi

  if grep -qE "${GIT}\s+commit\b.*\s(--all|-[a-zA-Z]*a[a-zA-Z]*)(\s|$)" <<<"$args"; then
    block "'git commit -a' stages all tracked changes without review."
  fi

  if grep -qE "${GIT}\s+(add|commit)\b" <<<"$args"; then
    for pattern in "${SECRET_FILE_PATTERNS[@]}"; do
      if grep -qiE "$pattern" <<<"$args"; then
        block "Detected a potential secret file in a git command (pattern: ${pattern})."
      fi
    done
  fi
done < <(segments "$COMMAND")

exit 0
