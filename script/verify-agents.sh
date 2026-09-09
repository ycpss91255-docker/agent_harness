#!/usr/bin/env bash
# Verify that each agent can reach the shared skills and hooks.
#
# Three independent checks:
#   1. registered  With tool use forbidden, the agent can still name
#                  probe-marker -> the skill was loaded natively into context,
#                  not found by the agent searching the filesystem.
#   2. used        The agent emits the marker string, which appears only in the
#                  body of SKILL.md.
#   3. hook        hook-probe.log gains a line carrying THIS RUN's nonce and
#                  this agent's own name -- or, for Codex, gains no such line
#                  at all. See CHECK 3 below.
#
# Checking only (2) gives false positives: an agent can grep the repo, read the
# file and echo the marker, which looks like a pass but proves nothing about
# the shared mechanism.
#
# CHECK 3 USED TO PROVE NOTHING. It truncated hook-probe.log, launched the
# agent, and asserted `[ -s "$LOG" ]` -- "the file is not empty". Every line the
# probe writes looked the same (agent=unknown, because nothing ever set
# AGENT_NAME), so what the assertion really said was "somebody ran a hook in
# this repo in the last few seconds". This machine runs several Claude Code
# sessions against this repo at once: an idle window of 45 seconds, with this
# script not running at all, collected 7 lines. Codex, for which the probe hook
# was not wired at all, scored PASS on that traffic -- a check that nothing in
# the tree could have made true, passing.
#
# Two things make it mean something now, and NEITHER is optional in the probe:
# test_probe.sh fires on every Bash call in this repo during ordinary work, so
# it defaults both fields rather than requiring them.
#
#   AGENT_NAME   an env prefix on each hook command, in .claude/settings.json
#                and in .agents/hooks.json, so a line says which agent wrote it.
#                A prefix is a form both formats support because both agents run
#                a hook command through a shell: Claude Code expands
#                $CLAUDE_PROJECT_DIR inside the string, and agy documents `sh -c`
#                with the working directory set to the directory holding
#                hooks.json.
#   PROBE_NONCE  a fresh random token per probe, exported into the agent process
#                this script launches and inherited by the hook that process
#                spawns. AGENT_NAME alone cannot separate this run from a
#                concurrent Claude Code session in the same repo -- both say
#                agent=claude -- and timing cannot either.
#
# The log is NO LONGER TRUNCATED. `: > "$LOG"` discarded lines another session
# had written moments earlier, and with a nonce to grep for there is nothing to
# gain by it.
#
# CODEX IS INVERTED, NOT SKIPPED -- AND THE REASON HAS CHANGED. The inversion
# was put here because Codex was held to have no hook mechanism at all, so "a
# hook fired" could never be true for it. That premise expired: codex-cli
# 0.153.2 reads project hooks from <repo>/.codex/hooks.json, and one wired there
# demonstrably fires (2026-09-09). The inversion stays, on a narrower and still
# true statement: THIS REPO does not wire test_probe.sh for Codex. .codex/hooks
# .json names redirect_gh_issue.sh and nothing else, so no line carrying this
# run's nonce may appear while Codex is the agent under test.
#
# It still costs nothing and still catches something: a probe hook wired for
# Codex behind our backs, or the nonce leaking out of the Codex process into
# another agent's hook. What it no longer means is "Codex cannot run hooks".
#
# WIRING THE PROBE FOR CODEX IS A REAL OPTION AND IS DELIBERATELY NOT TAKEN
# HERE. It would need the AGENT_NAME prefix (Codex does run the command through
# a shell, so the prefix form works) and a command that locates the repo root
# itself, since Codex starts a hook in the SESSION's directory and sets no
# project-directory variable. It would also be gated twice over: the repo has to
# be a trusted project in ~/.codex/config.toml and the hook itself has to have
# been reviewed, and under `codex exec` both gates fail in silence. A FAIL here
# would then mean "trust is not set up on this machine" at least as often as it
# meant "the shared mechanism is broken", which is not what this script is for.
# Deciding that is a separate change, taken with a Codex run in hand.
#
# EXIT STATUS: 1 if any check reported FAIL, 0 otherwise. The old `exit 0` was
# not a decision -- it was there because the last `command -v` in the dispatch
# chain would otherwise have set the status -- and it left "did it pass?"
# answerable only by reading stdout, which is no use to a caller. An agent CLI
# that is not installed is SKIPPED and does not fail the run. Note that check 1
# rests on the model obeying "do not run any command and do not read any file",
# which is an instruction and not enforcement, so a non-zero exit is a reason to
# read the output rather than proof that the structure is broken.
# script/ci/ci.sh still does not run this script: it needs the three CLIs and
# their credentials, which is why it stays a local check.
#
# NOT COVERED HERE: redirect_gh_issue.sh, .agents/scripts/, and the dist/ copies
# of all three config files -- the payload a consumer actually installs. Nothing in
# this script reads any of them; a completely unwired redirect hook passes here
# in silence, because test_probe.sh is wired separately and still fires.
# script/ci/ci.sh already owns all three (check_hook_wiring, check_gh_issue,
# check_ship) and runs on every PR without needing an agent CLI. Whether this
# script should also drive them, and what that would duplicate, is a separate
# decision and is deliberately not taken here.
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

fails=0
verdict() { if [ "$1" = 1 ]; then echo PASS; else echo FAIL; fi; }
judge() {                         # judge <label> <0|1>
  [ "$2" = 1 ] || fails=$((fails + 1))
  printf -- '--- %-11s: %s\n' "$1" "$(verdict "$2")"
}
note() { printf '                 %s\n' "$*"; }

# One token per probe, unguessable so that no other session can be holding it.
# The fallback is not urandom-quality, but it is still per-process and
# per-second, which is all this needs to be distinct from a concurrent run.
new_nonce() {
  local n
  n="$(od -An -N12 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  [ -n "$n" ] || n="$$-$(date +%s)-${RANDOM}${RANDOM}"
  printf 'NONCE-%s' "$n"
}

run_one() {                       # run_one <name> <agent> <fires|none> <cmd...>
  local name="$1" agent="$2" expect="$3"; shift 3
  printf '\n===== %s =====\n' "$name"

  # 1. registered
  local reg out
  out="$("$@" "$P_LIST" </dev/null 2>&1)" || true
  reg=0; printf '%s' "$out" | grep -q "$SKILL" && reg=1
  judge registered "$reg"

  # 2. used, and 3. hook
  #
  # The nonce is exported onto the agent process itself, which is this script's
  # child; the hook is that process's own child and inherits the environment.
  # That is the only channel available: the token has to be fresh per run, and
  # rewriting a config file mid-run would race every other session in the repo.
  local nonce; nonce="$(new_nonce)"
  out="$(PROBE_NONCE="$nonce" "$@" "$P_USE" </dev/null 2>&1)" || true
  local use=0; printf '%s' "$out" | grep -q "$MARKER" && use=1
  judge used "$use"
  if [ "$use" = 1 ] && [ "$reg" = 0 ]; then
    note '^ marker returned without registration: the agent'
    note '  searched the filesystem; the shared path is NOT working'
  fi

  # 3. hook. Only the lines this run is responsible for: the log is shared with
  # every other session working in this repo, and is no longer truncated.
  local mine hk=0
  mine="$(grep -F "nonce=$nonce" "$LOG" 2>/dev/null)" || mine=""

  if [ "$expect" = none ]; then
    [ -z "$mine" ] && hk=1
    judge hook "$hk"
    if [ "$hk" = 1 ]; then
      note "(inverted: this repo wires no probe hook for $name, so the"
      note " assertion is that no line carries this run's nonce -- and none does)"
    else
      note "^ a probe line carries this run's nonce, and this repo wires no"
      note "  probe hook for $name. Something else reached the probe with it:"
      printf '%s\n' "$mine" | sed 's/^/                 /'
    fi
    return 0
  fi

  printf '%s' "$mine" | grep -q "agent=$agent" && hk=1
  judge hook "$hk"
  if [ "$hk" = 1 ]; then
    printf '%s\n' "$mine" | sed 's/^/                 /'
  elif [ -n "$mine" ]; then
    note "^ the nonce reached the probe but no line says agent=$agent:"
    printf '%s\n' "$mine" | sed 's/^/                 /'
  else
    note "^ no line carries this run's nonce: either the hook never fired,"
    note '  or PROBE_NONCE did not reach it'
  fi
  return 0
}

target="${1:-all}"
case "$target" in
  all|claude|codex|agy) ;;
  *) printf 'unknown target: %s\navailable: claude codex agy all\n' "$target" >&2
     exit 2 ;;
esac

maybe_run() {                     # maybe_run <id> <name> <fires|none> <cmd...>
  local id="$1" name="$2" expect="$3"; shift 3
  case "$target" in all|"$id") ;; *) return 0 ;; esac
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '\n===== %s =====\n' "$name"
    printf -- '--- %-11s: %s is not on PATH\n' skipped "$1"
    return 0
  fi
  run_one "$name" "$id" "$expect" "$@"
}

maybe_run claude "Claude Code" fires claude -p
maybe_run codex "Codex" none codex exec --skip-git-repo-check --sandbox read-only
# In headless mode agy does not scan the cwd for workspace customizations;
# --add-dir is required. Interactive mode discovers them on its own.
maybe_run agy "agy (Antigravity)" fires agy --add-dir "$ROOT" -p

printf '\n'
if [ "$fails" = 0 ]; then
  echo 'all checks passed'
  exit 0
fi
printf '%s check(s) failed\n' "$fails"
exit 1
