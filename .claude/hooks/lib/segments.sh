#!/usr/bin/env bash
# Shared helpers for the Bash PreToolUse hooks. Source it; do not execute.

# require_jq <hook-name>: fail closed (exit 2) when jq is missing.
require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "BLOCKED: jq is not installed, so $1 cannot inspect the command (failing closed)." >&2
    exit 2
  fi
}

# segments <command>: print one simple command per line.
# - drops heredoc bodies (text, not commands), keeping the line that opens them
# - splits on &&, ||, ;, | and newlines
segments() {
  local line delim="" strip_tabs=0 check
  local heredoc_re="<<(-?)[[:space:]]*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$delim" ]; then
      check=$line
      [ "$strip_tabs" -eq 1 ] && check=${check#"${check%%[!$'\t']*}"}
      [ "$check" = "$delim" ] && delim=""
      continue
    fi
    if [[ $line =~ $heredoc_re ]]; then
      delim=${BASH_REMATCH[2]}
      strip_tabs=0
      [ "${BASH_REMATCH[1]}" = "-" ] && strip_tabs=1
    fi
    sed -E 's/(&&|\|\||;|\|)/\n/g' <<<"$line"
  done <<<"$1"
}

# first_word <segment>: the program name, skipping VAR=x assignments and
# wrappers (sudo, env, time, command, nohup) and leading ( or {.
first_word() {
  local w words
  read -ra words <<<"$1"   # read -a does not glob-expand (unlike set -- $1)
  for w in "${words[@]}"; do
    w=${w#[({]}
    case "$w" in
      "" | *=* | sudo | env | time | command | nohup) continue ;;
      *) echo "$w"; return ;;
    esac
  done
}

# is_text_only <segment>: true when the segment only prints/searches text
# (commit messages, grep patterns, PR bodies) and does not re-execute it.
is_text_only() {
  grep -qE '\b(bash|sh|zsh)\s+-c\b|\beval\b|\bxargs\b' <<<"$1" && return 1
  case "$(first_word "$1")" in
    git | gh | echo | printf | grep | egrep | rg | cat | head | tail | less | wc) return 0 ;;
  esac
  return 1
}
