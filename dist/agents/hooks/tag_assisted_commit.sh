#!/usr/bin/env bash
# tag_assisted_commit.sh -- PreToolUse hook (Claude Code matcher "Bash",
# agy "*", Codex "*").
#
# ITS ONLY JOB: when the command about to run is a call to
# .agents/scripts/assisted-commit.sh, append the session and agent ids to that
# command, so the wrapper can put them in an Assisted-by trailer. It judges
# nothing, denies nothing, and touches no other command.
#
# WHY A REWRITE, AND NOT A FILE ON DISK
#
# The wrapper needs two ids that exist only inside the agent runtime. Neither is
# in the environment of the shell the command runs in, so something has to carry
# them across, and the carrier has to survive CONCURRENCY: several subagents
# commit at the same moment, each with its own agent id.
#
# A state file needs a key both sides can compute, and there is none. The hook
# payload has tool_use_id; the command's environment does not (`env | grep -c
# toolu_` is 0). The command string is recoverable from /proc/$PPID/cmdline, but
# only wrapped in the shell-snapshot preamble and re-quoted, so it is not
# byte-identical to tool_input.command -- and two subagents running the same
# command collide anyway.
#
# hookSpecificOutput.updatedInput has none of that. Claude Code's own hook
# documentation describes it as "Modified tool input (PreToolUse only)": the
# hook rewrites the very command that is about to run. Payload and command are
# correlated by the runtime, so concurrency is a non-issue by construction --
# three concurrent subagents were measured getting three distinct, correct agent
# ids in three real commits, twice over.
#
# additionalContext, the sibling field, is the near miss: it is "Text injected
# into model context", so it reaches the model and never the shell. Hook stdout
# is not piped to the command.
#
# APPENDED, NEVER PREPENDED. Permissions are re-evaluated against the REWRITTEN
# command. Rewriting to `export ASSISTED_AGENT=...; ./assisted-commit.sh ...`
# was measured being DENIED under an allowlist of `Bash(./assisted-commit.sh:*)`
# that the same command passed with the hook removed: the prefix had changed.
# Appending `--assisted-...=` arguments leaves the prefix intact, so the
# allowlist still matches. That is why the wrapper takes its fields as argv.
#
# THE SENTINEL. agent_id is present in the payload only when the hook fires from
# INSIDE a subagent; it is absent for the main thread, by design, even in an
# `--agent` session. So the hook injects `--assisted-agent=main` in that case
# rather than injecting nothing, because "the main thread has no agent id" has
# to be silent while "the hook never ran" has to be loud, and without the
# sentinel those two are the same observation. The wrapper renders it, as
# `agent:main`, so the distinction survives into the commit instead of living
# only on the stderr of the session that made it. `main` cannot be mistaken for
# a truncated id: the ids are hex, `m` is not a hex digit, and the wrapper cuts
# ids to eight characters while `main` is four. The one thing indistinguishable
# from it would be a runtime reporting an agent_id that is literally `main` --
# ID_RE below accepts that string like any other -- which no measured id is;
# see doc/agents/commit-trailer.md.
#
# CODEX NEEDS ONE MORE FIELD, AND IT IS A SECURITY DECISION.
# Codex 0.153.2 has the same hook system, reads project hooks from <repo>/.codex/
# and accepts the same hookSpecificOutput object -- and its PreToolUse handler
# DISCARDS an updatedInput that does not come with permissionDecision "allow".
# Measured: without it, `hook: PreToolUse Failed`, the rewrite dropped, and the
# ORIGINAL command run instead. So on Codex this hook also grants permission.
#
# Granting permission is exactly why the match below is narrow. The hook says
# "allow" only for a command whose first word is the commit wrapper, only when
# nothing follows that command, and only after appending its own arguments to
# it. It never emits a decision on any other command, and it never emits one on
# Claude Code at all, where updatedInput needs no decision and an "allow" would
# waive a permission prompt the author is entitled to.
#
# The tool is read from the PROCESS TREE, not from the environment. There is no
# environment marker that answers for both agents: CLAUDECODE is native to
# Claude Code, and Codex exports nothing equivalent. The hook is a direct child
# of the agent, so the walk is short and reliable, and it is the same detection
# the wrapper uses for the human path.
#
# WHAT IT REFUSES TO REWRITE, and why the wrapper is loud instead
#
# The fields are APPENDED to the end of the command string, so they only land in
# the wrapper's argv if the wrapper's argument list is what the end of the
# string is. `./assisted-commit.sh -m x | tee log` would put them on tee. So the
# command is scanned for anything that could end it or redirect it -- `; | & < >
# ( ) ` $( #` and a newline -- OUTSIDE quotes, and a command carrying any of
# them at top level is left exactly as it was.
#
# The scan is quote-aware and not a grep, and that is the whole reason it is
# written out rather than done with a pattern: commit messages are made of these
# characters. `-m "hooks: handle > and |"` is an ordinary commit and must still
# be tagged. Inside quotes nothing can terminate the command, so a quoted region
# is skipped whole; unbalanced quotes, or a trailing backslash after the string
# is trimmed, mean the scan cannot say where the command ends, and both are
# treated as "leave it alone".
#
# Leaving it alone is not silent overall: the wrapper still sees an agent in its
# own process tree, finds nothing injected, and says so loudly on stderr while
# making the commit. A missed rewrite therefore costs a warning, never a wrong
# trailer and never a lost commit.
#
# AND WHAT IT REFUSES BECAUSE THE COMMAND IS ALREADY TAGGED. A command that
# already carries ANY --assisted-<field>= is left alone, not just one carrying
# --assisted-tool=. The guard is "do not tag a command that has been tagged
# already", and any one of the fields is evidence of that: a command carrying
# only a stray --assisted-agent= was measured getting a full set appended to its
# RIGHT, and the wrapper then had two agent ids to choose between. The wrapper
# now takes the rightmost, so it would choose correctly -- this guard is the
# second layer, and it means the hook never builds that command in the first
# place.
#
# It errs toward declining: a commit MESSAGE containing the text
# `--assisted-agent=` trips it too, and that costs the wrapper's loud warning
# and a tool-only trailer. That is the safe direction. The other one is a wrong
# id, which no reader can tell from a right one.
#
# THIS HOOK NEVER BLOCKS ANYTHING. Every failure path -- no payload, no python3,
# an unreadable payload, an unrecognised agent, a command it will not rewrite --
# prints nothing and exits 0, which is "no opinion". A hook that could refuse a
# commit because it could not work out an id would be trading the author's work
# for a trailer.
#
# It is, however, FAIL-CLOSED against its own syntax, like every hook here: a
# shell syntax error makes bash exit 2, which is PreToolUse's code for "block",
# so every Bash call in the session is denied until the file parses again.
# script/ci/ci.sh check_assisted_commit runs `bash -n` over it for that reason.
#
# python3 does the payload, the scan and the emit in one pass. The command
# string is arbitrary author text on its way back out as JSON, so it needs real
# escaping rather than the hand-rolled kind that is safe for a fixed message;
# and the scan is a small state machine that bash regexes cannot express. If
# python3 is absent the hook stays silent and the wrapper's loud path covers it.
#
# agy runs the same script from .agents/hooks.json, whose working directory is
# .agents/ -- hence the `./hooks/...` command there. Codex runs it through a
# shell from the SESSION's directory with no project-directory variable set,
# hence the "$(git rev-parse --show-toplevel)/..." command in .codex/hooks.json.
#
# Driven by script/ci/ci.sh check_assisted_commit with real stdin payloads.

set -uo pipefail

# The basename the rewrite is keyed on. It is the wrapper's file name rather
# than a full path, because the path differs by agent -- $CLAUDE_PROJECT_DIR/...,
# ./.agents/scripts/..., an absolute one -- and the name is the part that is the
# same everywhere.
readonly WRAPPER='assisted-commit.sh'

# Same walk as the wrapper's, and for the same reason: no environment marker
# answers for both agents. ASSISTED_BY_TOOL overrides it when set, which is what
# lets script/ci/ci.sh drive the Codex branch on a machine running Claude Code.
detect_tool() {
  if [[ ${ASSISTED_BY_TOOL+set} == set ]]; then
    printf '%s' "$ASSISTED_BY_TOOL"
    return 0
  fi
  local pid="$$" depth=0 comm ppid line rest
  while ((depth++ < 32)); do
    [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] || break
    (("$pid" > 1)) || break
    comm=""; ppid=""
    if [[ -r "/proc/$pid/stat" ]]; then
      line="$(< "/proc/$pid/stat")"
      rest="${line#*(}"; comm="${rest%)*}"
      rest="${line##*)}"
      read -r _ ppid _ <<<"$rest"
    elif command -v ps >/dev/null 2>&1; then
      comm="$(ps -o comm= -p "$pid" 2>/dev/null)"
      ppid="$(ps -o ppid= -p "$pid" 2>/dev/null)"
    else
      break
    fi
    comm="${comm##*/}"
    comm="${comm//[[:space:]]/}"
    ppid="${ppid//[[:space:]]/}"
    case "$comm" in
      claude|claude-code) printf 'claude-code'; return 0 ;;
      codex|codex-cli)    printf 'codex';       return 0 ;;
    esac
    [[ "$ppid" == "$pid" ]] && break
    pid="$ppid"
  done
  [[ "${CLAUDECODE:-}" == 1 ]] && { printf 'claude-code'; return 0; }
  return 0
}

# Read from a quoted heredoc so the body can use whichever quotes read best;
# `python3 -c` would otherwise have to be written without a single quote in it.
IFS= read -r -d '' TAGGER <<'TAGGER_PY'
import json, re, sys

tool, wrapper = sys.argv[1], sys.argv[2]

# The first word of the command, after any leading VAR=value assignments, is the
# wrapper -- at any path, or at none. Anchored at the start, so the name
# appearing later in the string (in a message, in a second segment of a chain)
# is not a match, and a name that merely ENDS in the wrapper's -- say
# not-assisted-commit.sh -- is not one either, because what precedes it has to
# be a "/" or nothing.
WRAPPER_RE = re.compile(
    r"^\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*/)?"
    + re.escape(wrapper) + r"(?=\s|$)")

TOOL_RE = re.compile(r"^[a-z][a-z0-9-]{0,31}$")
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")

# Any field of the tagging, present or future, rather than --assisted-tool=
# alone. The "=" is required so that prose about the flags is not a match, and
# the field name is left open so a fourth field does not silently fall outside
# the guard the day somebody adds one.
TAGGED_RE = re.compile(r"--assisted-[a-z][a-z0-9-]*=")

# Anything that could end this command or send it somewhere else. Not "anything
# shell-special": $ and " and ` inside a quoted message expand, but they cannot
# terminate the command, and the fields are appended to its end.
BREAKERS = set(";|&<>()`\n#")


def ends_here(cmd):
    """True when the end of the string is the end of this one command."""
    i, n = 0, len(cmd)
    while i < n:
        c = cmd[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            j = cmd.find("'", i + 1)
            if j < 0:
                return False          # unterminated; nothing can be said
            i = j + 1
            continue
        if c == '"':
            i += 1
            while i < n and cmd[i] != '"':
                i += 2 if cmd[i] == "\\" else 1
            if i >= n:
                return False          # unterminated
            i += 1
            continue
        if c in BREAKERS:
            return False
        if c == "$" and i + 1 < n and cmd[i + 1] == "(":
            return False
        i += 1
    return True


def quiet():
    raise SystemExit(0)


if not TOOL_RE.match(tool):
    quiet()

try:
    payload = json.load(sys.stdin)
except Exception:
    quiet()
if not isinstance(payload, dict):
    quiet()

tool_input = payload.get("tool_input")
if not isinstance(tool_input, dict):
    quiet()
command = tool_input.get("command")
if not isinstance(command, str) or not command.strip():
    quiet()

if not WRAPPER_RE.match(command):
    quiet()
# Already tagged, by whoever put the field there. Appending a second set would
# leave the wrapper resolving a precedence question it should never be asked,
# and ANY of the fields says the command has been tagged -- keying this on
# --assisted-tool= alone let a stray --assisted-agent= straight through.
if TAGGED_RE.search(command):
    quiet()

trimmed = command.rstrip()
# A trailing backslash was a line continuation whose newline has just been
# trimmed; appending after it would escape the space instead of continuing.
if not trimmed or trimmed.endswith("\\") or not ends_here(trimmed):
    quiet()

session = payload.get("session_id")
agent = payload.get("agent_id")

fields = ["--assisted-tool=" + tool]
if isinstance(session, str) and ID_RE.match(session):
    fields.append("--assisted-session=" + session)
# Absent for the main thread, by design. The sentinel says the hook spoke, so
# the wrapper can write agent:main in silence instead of reporting itself
# broken. An agent_id that is present but malformed falls here too, and the
# wrapper has no way to tell that from the main thread.
fields.append(
    "--assisted-agent=" + (agent if isinstance(agent, str) and ID_RE.match(agent)
                           else "main"))

# The WHOLE tool input, with one key replaced. Emitting only the command would
# hand the runtime an input object that has lost the description and timeout it
# came with.
updated = dict(tool_input)
updated["command"] = trimmed + " " + " ".join(fields)

specific = {"hookEventName": "PreToolUse", "updatedInput": updated}
if tool == "codex":
    # Codex discards an updatedInput that arrives without a decision: measured
    # as "hook: PreToolUse Failed" and the original command run instead. The
    # decision is scoped to this one command shape and is emitted nowhere else.
    specific["permissionDecision"] = "allow"
    specific["permissionDecisionReason"] = (
        "tag_assisted_commit.sh appended the Assisted-by fields to this "
        + wrapper + " call")
print(json.dumps({"hookSpecificOutput": specific}))
TAGGER_PY

main() {
  # Drained FIRST, and unconditionally. Every path below can decide to say
  # nothing, and a hook that exits without reading leaves the runtime writing
  # the payload into a closed pipe.
  local payload; payload="$(cat)"
  [[ -n "$payload" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local tool; tool="$(detect_tool)"
  [[ -n "$tool" ]] || return 0
  printf '%s' "$payload" | python3 -c "$TAGGER" "$tool" "$WRAPPER" 2>/dev/null
  return 0
}

main "$@"
