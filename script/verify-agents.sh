#!/usr/bin/env bash
# Verify that each agent can reach the shared skills and hooks.
#
# Three independent checks:
#   1. registered  With tool use forbidden, the agent can still name
#                  probe-marker -> the skill was loaded natively into context,
#                  not found by the agent searching the filesystem.
#   2. used        The agent emits the marker string, which appears only in the
#                  body of SKILL.md.
#   3. hook        hook-probe.log gains a new line.
#
# Checking only (2) gives false positives: an agent can grep the repo, read the
# file and echo the marker, which looks like a pass but proves nothing about
# the shared mechanism.
#
# Usage: script/verify-agents.sh [claude|codex|agy|all]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
LOG="$ROOT/hook-probe.log"
MARKER='PROBE-MARKER-OK-7Q4X'
SKILL='probe-marker'
P_LIST='Do not run any command and do not read any file. Based only on what you already know, list the names of the skills currently available to you.'
P_USE='Give me the PROBE MARKER.'

verdict() { if [ "$1" = 1 ]; then echo PASS; else echo FAIL; fi; }

run_one() {
  local name="$1"; shift
  printf '\n===== %s =====\n' "$name"

  # 1. registered
  local reg out
  out="$("$@" "$P_LIST" </dev/null 2>&1)" || true
  reg=0; printf '%s' "$out" | grep -q "$SKILL" && reg=1
  printf -- '--- registered : %s\n' "$(verdict $reg)"

  # 2. used, and 3. hook
  : > "$LOG"
  out="$("$@" "$P_USE" </dev/null 2>&1)" || true
  local use=0; printf '%s' "$out" | grep -q "$MARKER" && use=1
  printf -- '--- used       : %s\n' "$(verdict $use)"
  if [ "$use" = 1 ] && [ "$reg" = 0 ]; then
    echo '                 ^ marker returned without registration: the agent'
    echo '                   searched the filesystem; the shared path is NOT working'
  fi
  local hk=0; [ -s "$LOG" ] && hk=1
  printf -- '--- hook       : %s\n' "$(verdict $hk)"
  [ "$hk" = 1 ] && sed 's/^/                 /' "$LOG"
  return 0
}

target="${1:-all}"
[ "$target" = all ] || [ "$target" = claude ] && command -v claude >/dev/null \
  && run_one "Claude Code" claude -p
[ "$target" = all ] || [ "$target" = codex ] && command -v codex >/dev/null \
  && run_one "Codex" codex exec --skip-git-repo-check --sandbox read-only
# In headless mode agy does not scan the cwd for workspace customizations;
# --add-dir is required. Interactive mode discovers them on its own.
[ "$target" = all ] || [ "$target" = agy ] && command -v agy >/dev/null \
  && run_one "agy (Antigravity)" agy --add-dir "$ROOT" -p
exit 0
