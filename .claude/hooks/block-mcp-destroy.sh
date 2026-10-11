#!/usr/bin/env bash
# Hook: block-mcp-destroy.sh (PreToolUse on MCP Terraform tools)
# Purpose: Blocks destroy/delete operations sent through MCP Terraform tools,
#          which bypass the Bash-level block-destroy.sh hook.
# Covers:
#   - hashicorp terraform-mcp-server (the server configured in .mcp.json):
#       delete_* tools (workspaces, variables, variable sets) -> block
#       run tools whose input mentions destroy (e.g. create_run as a destroy run) -> block
#       apply_run -> ask (the user runs applies)
#   - awslabs terraform server (ExecuteTerraformCommand/ExecuteTerragruntCommand):
#       command == destroy -> block
# How: exit 2 = deny (reason on stderr); "ask" is returned as JSON on stdout.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: jq is not installed, so block-mcp-destroy.sh cannot inspect the call (failing closed)." >&2
  exit 2
fi

INPUT=$(cat)
TOOL_NAME=$(jq -r '.tool_name // empty' <<<"$INPUT")
TOOL_INPUT=$(jq -c '.tool_input // {}' <<<"$INPUT")
COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT")

block() {
  {
    echo "BLOCKED: $1"
    echo ""
    echo "Destroying infrastructure must be done manually with explicit human oversight."
    echo "Run it directly in your terminal or the HCP Terraform UI (not via Claude Code)."
  } >&2
  exit 2
}

# awslabs server
if grep -qE '(ExecuteTerraformCommand|ExecuteTerragruntCommand)$' <<<"$TOOL_NAME"; then
  if grep -qiE '(^|[^a-z])(destroy|run-all destroy)' <<<"$COMMAND"; then
    block "'${COMMAND}' via MCP Terraform tool is not allowed."
  fi
  exit 0
fi

# hashicorp terraform-mcp-server
if grep -qE '^mcp__terraform-mcp-server__' <<<"$TOOL_NAME"; then
  OP=${TOOL_NAME#mcp__terraform-mcp-server__}

  if grep -qE '^delete_' <<<"$OP"; then
    block "MCP tool '${OP}' deletes Terraform resources."
  fi
  # Only run tools (registry searches may legitimately query "destroy"). Match
  # destroy-named keys set to true, or run-type values equal to "destroy";
  # is_destroy:false and workspace names containing "destroy" stay allowed.
  if grep -qE 'run' <<<"$OP" && jq -e '[.. | objects | to_entries[]
      | select((.key | test("destroy"; "i")) and .value == true
               or (.key | test("type|operation|mode"; "i")) and (.value | type == "string") and (.value | test("^destroy$"; "i")))]
      | length > 0' <<<"$TOOL_INPUT" >/dev/null; then
    block "MCP tool '${OP}' was called with a destroy option."
  fi
  if [ "$OP" = "apply_run" ]; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask",
      permissionDecisionReason: "apply_run applies a Terraform run; the user approves applies explicitly."}}'
    exit 0
  fi
fi

exit 0
