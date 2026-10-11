#!/usr/bin/env bash
# Usage: run-hook-tests.sh <hooks-dir> <bash-cases.tsv> <mcp-cases.tsv>
# Bash cases: expected<TAB>hook<TAB>command; expected is 0, 2 or ask.
set -uo pipefail
HOOKS=$1; BASH_CASES=$2; MCP_CASES=$3
pass=0; fail=0

# A syntax error makes bash exit 2, which silently turns a hook into "block everything"
for f in "$HOOKS"/*.sh "$HOOKS"/lib/*.sh; do
  bash -n "$f" || { echo "SYNTAX ERROR: $f"; fail=$((fail+1)); }
done

check() { # expected hook json label
  local expected=$1 hook=$2 json=$3 label=$4 out rc got
  out=$(bash "$HOOKS/$hook.sh" <<<"$json" 2>/dev/null); rc=$?
  if [ "$rc" -eq 0 ] && grep -q '"permissionDecision": *"ask"' <<<"$out"; then got=ask; else got=$rc; fi
  if [ "$got" = "$expected" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL [$hook] expected=$expected got=$got :: $label"; fi
}

while IFS=$'\t' read -r expected hook cmd; do
  [ -z "$expected" ] && continue
  cmd=$(printf '%b' "$cmd")  # \n in the TSV = newline (heredocs, multi-line messages)
  check "$expected" "$hook" "$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')" "$cmd"
done <"$BASH_CASES"

while IFS=$'\t' read -r expected tool input; do
  [ -z "$expected" ] && continue
  check "$expected" block-mcp-destroy "$(jq -nc --arg t "$tool" --argjson i "$input" '{tool_name:$t,tool_input:$i}')" "$tool $input"
done <"$MCP_CASES"

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
