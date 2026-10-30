#!/usr/bin/env bash
# assisted-commit.sh -- git commit, carrying an Assisted-by trailer when an
# agent is the one committing.
#
#   .agents/scripts/assisted-commit.sh -m "hooks: wire the tagger for Codex"
#   .agents/scripts/assisted-commit.sh -a -m "docs: state the trailer format"
#
# Every argument this script does not claim itself is forwarded to `git commit`
# untouched. It claims `--print-command`, `-h` and `--help` at the front, and
# the three `--assisted-*` fields the hook appends to the tail. This is
# `git commit` with one thing added, so anything git accepts, this accepts.
#
# THE TRAILER
#
#   Assisted-by: claude-code session:d5c2a46d agent:a021dc30
#   Assisted-by: claude-code session:d5c2a46d agent:main
#   Assisted-by: codex session:01a07ed9 agent:b7f21e44
#
# Three fields: the tool, the session, the agent. Ids are truncated to eight
# characters, like a git short hash -- a prefix is still enough to find the full
# id locally, and the full ones make the line unreadable. The agent field is a
# truncated id when a subagent committed and the literal `main` when the main
# thread did; `main` is a word rather than an id, so nothing truncates it and
# nothing checks it against the shape of an id.
#
# NO MODEL, NO CLI VERSION. Both were considered and dropped: Claude Code
# cannot report the model it is running, so the field would be present for one
# tool and absent for the other, and an asymmetric field is worse than no field
# -- a reader cannot tell "this tool does not report it" from "this commit did
# not have one".
#
# `Assisted-by:`, NOT `Co-Authored-By:`. This is the convention Apache Calcite,
# JMeter and Cloudberry converged on, and the reason is mechanical rather than
# stylistic: git and GitHub read every name in a Co-Authored-By trailer as an
# AUTHOR of the commit. A tool listed there asserts authorship. `Assisted-by:`
# asserts what actually happened -- a tool was involved -- and no tool of git's
# reads it as a person.
#
# THE HUMAN PATH IS SILENT AND SUCCESSFUL. A commit with no agent anywhere near
# it emits no trailer, prints nothing at all, and exits 0. That is not a
# degraded mode; it is the ordinary one. A wrapper that nags on every hand-typed
# commit gets uninstalled within a week, and then it tags nothing.
#
# WHERE THE IDS COME FROM
#
# Not from here. A process cannot ask the agent that started it for its session
# or agent id -- neither is in the environment of the shell an agent runs a
# command in. They arrive in this script's own argv, put there by the PreToolUse
# hook .agents/hooks/tag_assisted_commit.sh, which is handed both by the runtime
# and rewrites the command that is about to run:
#
#   ./assisted-commit.sh -m "msg"
#     becomes
#   ./assisted-commit.sh -m "msg" --assisted-tool=claude-code \
#       --assisted-session=<id> --assisted-agent=<id>
#
# The payload and the command are correlated by the runtime, not by a key this
# repo computes, so concurrent subagents cannot cross their ids: three of them
# committing at once were measured getting three distinct, correct agent ids.
# Every state-file scheme needs a shared key, and there is none -- the tool_use
# id is in the hook payload and nowhere in the command's environment.
#
# APPENDED, NEVER PREPENDED, and that is not a style choice. Permissions are
# re-evaluated against the REWRITTEN command, so rewriting to
# `export X=...; ./assisted-commit.sh ...` changes the command's prefix and an
# allowlist entry of `Bash(./assisted-commit.sh:*)` stops matching it -- measured
# as a denial of a command that ran fine with the hook removed. Appending leaves
# the prefix alone, so the allowlist still matches.
#
# THE HOOK HAS THE LAST WORD, and that is a correctness rule rather than a
# preference. The hook is the only thing that knows the ids; a caller typing
# `--assisted-agent=...` by hand -- almost always a line copied out of a
# transcript, where the hook's rewrite is visible -- knows only what was true in
# some earlier session. So the fields are read RIGHT TO LEFT and the rightmost
# value of each wins, which is the hook's, because the hook appends. A leftover
# to the left of the hook's `--assisted-tool=` is consumed (so it cannot reach
# git), ignored (so it cannot pre-empt the hook, nor fill a field the hook
# deliberately left out), and reported on stderr.
#
# There is no way to FORBID a caller from writing these, and pretending
# otherwise would be a lie in a comment: argv is the hook's only channel -- an
# environment variable would have to be prepended to the command and that
# changes the prefix an allowlist matches, see above -- so the wrapper cannot
# tell the hook's use of that channel from anybody else's. What it can do, and
# does, is make position authoritative. Which is also what lets
# script/ci/ci.sh drive every path here without a live hook, through the same
# channel the hook uses, rather than through a test-only door that would then
# exist in production too.
#
# THE THREE-WAY DISCRIMINATION, and why the hook always speaks
#
#   human               nothing injected, no agent in the process tree
#                       -> no trailer, exit 0, nothing printed
#   agent, subagent     --assisted-agent=<id>
#                       -> the full trailer, agent:<id>
#   agent, main thread  --assisted-agent=main
#                       -> the full trailer, agent:main, and this is silent
#   agent, hook broken  an agent is running, nothing was injected
#                       -> LOUD on stderr, and the commit is still made
#
# The main thread genuinely has no agent id: Claude Code's payload carries
# agent_id only from inside a subagent, and it is absent for the main thread by
# design rather than by failure. The field says `main`, and that is NOT a
# placeholder standing in for a value this could not read: it names which thread
# committed, which is something that IS known. `agent:unknown` would be the
# placeholder, and it is still refused, because `git log --grep` cannot tell one
# of those from a real id. `agent:main` states a fact, and `git log --grep
# 'agent:main'` selects exactly the main-thread commits.
#
# Which is why the hook injects `--assisted-agent=main` rather than injecting
# nothing. Without that sentinel, "the main thread has no agent id" and "the
# hook never ran" are the same observation, and the second one has to be loud
# while the first has to be silent. Rendering the sentinel keeps those two apart
# in the commit itself, and not only on the stderr of the session that made it.
# `main` cannot be read as a truncated id: real ids are hex -- Claude Code's are
# `a` and 16 hex digits -- `m` is not a hex digit, and every id here is cut to
# eight characters while `main` is four. What would collide is a runtime handing
# the hook an agent_id that is literally `main`; nothing at this layer could
# tell that from the sentinel, and it is recorded in the document below.
#
# A BROKEN LOOKUP IS LOUD AND STILL COMMITS. If an agent is running and nothing
# was injected, the trailer records what can still be established -- the tool,
# which the process tree answers without any hook at all -- and stderr says the
# rest is missing and why. The commit is never lost over it: refusing would turn
# a wiring problem into lost work, and a silent partial trailer would let a
# broken hook look exactly like normal operation for months.
#
# THE SESSION ID IS NOT READ FROM THE ENVIRONMENT, although it is there.
# Claude Code exports CLAUDE_CODE_SESSION_ID, and using it as a second source
# would fill in the session field on the broken path. It is deliberately not
# used. A second, silent channel would repair exactly the symptom that the loud
# path exists to reveal, so a hook that had stopped firing would go unnoticed
# until the day somebody wanted an agent id; and it is Claude-Code-only, so it
# would make Codex the asymmetric case for no gain. One channel, and it is
# noisy when it breaks.
#
# `--print-command`, NOT `--dry-run`. `git commit --dry-run` already exists and
# means something else -- it reports what would be committed -- and an unclaimed
# argument here is forwarded to git, so taking that name would silently change a
# flag git defines. `--print-command` prints the exact `git commit` invocation
# this would run, quoted so it can be pasted, and runs nothing. It is a
# convenience for a human. NOTHING MAY DEPEND ON IT FOR SAFETY: it is a flag
# this script honours, so it is worth exactly what this script's correctness is
# worth. script/ci/ci.sh keeps itself away from this repository by its
# ENVIRONMENT -- a throwaway repo under /tmp with GIT_DIR pinned into it -- and
# never by this flag. A suite in this repo once relied on a flag the code under
# test honoured and filed three real GitHub issues when that code had a defect.
#
# WHERE THIS LIVES: dist/agents/scripts/assisted-commit.sh, linked by init.sh to
# .agents/scripts/assisted-commit.sh in every repo that installs the harness.
# That second path is the one to name anywhere, because it is the only one that
# is true in a consumer's repo as well as in this one. Under .agents/ rather
# than .claude/ because Codex calls it too.
#
# Driven by script/ci/ci.sh check_assisted_commit.

set -uo pipefail

readonly TRAILER_KEY='Assisted-by'
readonly ID_LEN=8
# The sentinel the hook injects when the runtime reported no agent id, and the
# value the agent field then carries. See the discrimination table above.
readonly MAIN_THREAD='main'
readonly DOC='doc/agents/commit-trailer.md'
# The DELIVERED paths. dist/ is not what anybody runs; these are what init.sh
# creates in every install, including this repo's own.
readonly HOOK_PATH='.agents/hooks/tag_assisted_commit.sh'
readonly SELF_PATH='.agents/scripts/assisted-commit.sh'
# `git commit --trailer` arrived in git 2.32. Older git answers an unknown
# option by refusing the commit, which is the one outcome this script must never
# produce, so the version is asked first and the trailer is dropped instead.
readonly GIT_TRAILER_MAJOR=2
readonly GIT_TRAILER_MINOR=32

# Repo-relative, so a document is looked for at the repository root rather than
# in whatever directory the agent happened to be standing in.
doc_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -d "${CLAUDE_PROJECT_DIR}" ]]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  local root=""
  command -v git >/dev/null 2>&1 && root="$(git rev-parse --show-toplevel 2>/dev/null)"
  printf '%s' "${root:-$PWD}"
}

# The citation line for a document, or nothing at all if this install does not
# carry it. dist/ ships this script and does not ship doc/, so in a consumer's
# repo the document below does not exist -- and a message ending "see <file>"
# for a file the reader was never given reads as a broken install and tells them
# nothing. Every message here therefore states the rule in its own words and
# appends the pointer only where the pointer resolves.
cite() {                          # cite <document>
  [[ -f "$(doc_root)/$1" ]] || return 0
  printf 'see %s' "$1"
}

usage() {
  cat >&2 <<'USAGE'
usage:
  assisted-commit.sh [--print-command] [git commit flags...]

  git commit, plus an Assisted-by trailer when an agent is the one committing.
  Every other argument is forwarded to git commit untouched.

  --print-command  print the exact git commit invocation this would run,
                   quoted so it can be pasted, and run nothing. Not --dry-run:
                   git commit --dry-run already means something else, and this
                   forwards it.
  -h, --help       this text

  A commit with no agent involved gets no trailer, prints nothing extra and
  exits 0. That is the ordinary path, not a degraded one.
USAGE
  local c; c="$(cite "$DOC")"
  [[ -n "$c" ]] && printf '%s\n' "$c" >&2
  return 0
}

# LOUD means stderr, named, and saying what to do. It never changes the exit
# status: every message this script prints is about the TRAILER, and the commit
# is the thing the caller asked for.
warn() {                          # warn <headline> <line>...
  printf 'assisted-commit.sh: %s\n' "$1" >&2
  shift
  local line
  # An empty line is a citation that was dropped because this install does not
  # carry the document; printing it would leave a blank indented line where a
  # reader expects a pointer.
  for line in "$@"; do [[ -n "$line" ]] && printf '  %s\n' "$line" >&2; done
  return 0
}

fail_usage() {                    # fail_usage <line>...
  local line
  for line in "$@"; do printf 'assisted-commit.sh: %s\n' "$line" >&2; done
  usage
  exit 2
}

# The two vocabularies, kept narrow on purpose. Everything that reaches the
# trailer has been through one of them, so the line cannot acquire a space, a
# newline or a quote from an id -- and neither can the command the hook builds,
# which is the same argument one step earlier.
valid_tool() { [[ "$1" =~ ^[a-z][a-z0-9-]{0,31}$ ]]; }
valid_id()   { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$ ]]; }

# WHICH AGENT IS RUNNING THIS, asked of the process tree rather than the
# environment. There is no environment marker that answers for both: CLAUDECODE
# is native to Claude Code, and Codex exports nothing equivalent to the shells
# it starts. The process tree answers for both, needs no hook, and is what makes
# the human path silent -- a hand-typed commit has no agent above it.
#
# ASSISTED_BY_TOOL overrides the walk when it is SET, including when it is set
# to the empty string, which declares that no agent is present. It exists for
# two real cases: a container or a restricted image where neither /proc nor ps
# answers, and script/ci/ci.sh, which has to drive the human path and both agent
# paths from a session that is itself an agent. It selects which name reaches
# the trailer and nothing else -- it cannot decide which repository is
# committed to, so it is not a safety control and nothing in the suite treats it
# as one.
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
      # Field 2 is the command in parentheses and may itself contain spaces and
      # parentheses, so it is bounded by the LAST ")" rather than by field
      # counting; field 4, two words after that, is the parent pid.
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
  # Native to Claude Code and documented by it. Only ever consulted after the
  # walk, so it is a backstop for an unreadable process table rather than the
  # mechanism -- there is no equivalent for Codex, and a detection that worked
  # for one agent would quietly make the other one the broken case.
  [[ "${CLAUDECODE:-}" == 1 ]] && { printf 'claude-code'; return 0; }
  return 0
}

# Quote one argument the way a person would have to type it, so --print-command
# emits a line that can be pasted into a shell and mean the same thing.
shell_quote() {                   # shell_quote <arg>
  local s="$1"
  if [[ -n "$s" && "$s" =~ ^[A-Za-z0-9_@%+=:,./-]+$ ]]; then
    printf '%s' "$s"
  else
    printf "'%s'" "${s//\'/\'\\\'\'}"
  fi
}

git_has_trailer_flag() {
  local v major minor
  v="$(git --version 2>/dev/null)" || return 1
  [[ "$v" =~ ([0-9]+)\.([0-9]+) ]] || return 1
  major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"
  ((major > GIT_TRAILER_MAJOR)) && return 0
  ((major == GIT_TRAILER_MAJOR && minor >= GIT_TRAILER_MINOR))
}

main() {
  local print_only=0
  # This script's own flags are read only at the FRONT. Everything after the
  # first argument that is not one of them belongs to git, and git has flags of
  # both these names.
  while (($#)); do
    case "$1" in
      --print-command) print_only=1; shift ;;
      -h|--help)       usage; exit 0 ;;
      *)               break ;;
    esac
  done

  # The hook's fields are popped off the TAIL, which is the only place it puts
  # them. Popping the tail rather than filtering the whole argument list means
  # this needs to know nothing about which git flags take a value: a message
  # that happens to read `--assisted-tool=x` is a value in the middle of the
  # list and is left alone, and a `--` before a pathspec keeps the pathspec it
  # was written in front of.
  #
  # READ RIGHT TO LEFT, AND THE RIGHTMOST VALUE OF EACH FIELD WINS. The hook
  # appends, so its values are the rightmost ones and this hands it the last
  # word on every field it fills in. Assigning on every pass instead would let
  # the LEFTMOST duplicate survive, which is a caller's value beating the
  # hook's -- a wrong id that reads exactly like a right one.
  #
  # The hook's group is taken to START at its `--assisted-tool=`, which it
  # always emits first, and everything left of that is a leftover. The boundary
  # is what stops a leftover filling a field the hook deliberately OMITTED: a
  # stale `--assisted-session=` cannot supply the session for an injection that
  # carried none, which would be the same wrong id by a longer route.
  local -a argv=("$@")
  local n=${#argv[@]} last
  local tool_in="" session_in="" agent_in="" spoke=0 saw_session=0 saw_agent=0
  # closed: the hook's --assisted-tool= has been seen, so everything further
  # left predates the injection. stale: at least one field was dropped for that
  # reason, or for being a second value of a field already taken.
  local closed=0 stale=0
  while ((n > 0)); do
    last="${argv[n - 1]}"
    case "$last" in
      --assisted-tool=*|--assisted-session=*|--assisted-agent=*) ;;
      *) break ;;
    esac
    # Consumed either way. A field this script will not USE still must not reach
    # git, which answers an unknown option by refusing the commit.
    ((n--))
    if ((closed)); then stale=1; continue; fi
    spoke=1
    case "$last" in
      --assisted-tool=*)    tool_in="${last#*=}"; closed=1 ;;
      --assisted-session=*)
        if ((saw_session)); then stale=1
        else session_in="${last#*=}"; saw_session=1; fi ;;
      --assisted-agent=*)
        if ((saw_agent)); then stale=1
        else agent_in="${last#*=}"; saw_agent=1; fi ;;
    esac
  done
  argv=("${argv[@]:0:n}")

  # LOUD, because the interesting case is an agent replaying a command it read
  # in its own transcript, and that is exactly the case where the discarded id
  # was real, plausible and belonged to somebody else.
  if ((stale)); then
    warn 'Assisted-by fields already on the command line were ignored' \
      'the trailer is built from the fields the PreToolUse hook appended last,' \
      'so an --assisted-tool=, --assisted-session= or --assisted-agent= written' \
      'to the left of those is dropped rather than used. A wrong id is worse' \
      'than a missing one: git log cannot tell it from a right one.' \
      'remove them from the command and let the hook supply them.' \
      "$(cite "$DOC")"
  fi

  # Two independent questions, and the answers are not interchangeable. "Did
  # the hook speak?" is what the injected fields answer. "Is an agent running
  # this at all?" is what the process tree answers, with no hook involved --
  # and it is the one that has to be right when the hook is broken, because
  # that is the whole broken case.
  local tool=""
  if ((spoke)); then tool="$tool_in"; else tool="$(detect_tool)"; fi
  local present=0
  ((spoke)) && present=1
  [[ -n "$tool" ]] && present=1

  local trailer=""
  if ((present)); then
    if ! valid_tool "$tool"; then
      # Without a tool name there is no trailer to write: it is the field that
      # says what the line is about. Loud, and the commit still happens.
      warn 'no Assisted-by trailer: the tool name is unusable' \
        "got: \"$tool\"" \
        'a tool name is lower-case letters, digits and dashes, up to 32 of' \
        'them: claude-code, codex.' \
        "$(cite "$DOC")"
      tool=""
    fi

    if ((spoke == 0)) && [[ -n "$tool" ]]; then
      warn 'the Assisted-by trailer is incomplete: nothing was injected' \
        "an agent is running this commit ($tool), but the PreToolUse hook that" \
        'supplies the session and agent ids did not rewrite the command, so' \
        'those two fields cannot be filled in. The commit is being made anyway,' \
        'with the one field that can still be established.' \
        "wire $HOOK_PATH into this agent's PreToolUse config, and invoke" \
        "$SELF_PATH as a plain command: the hook does not rewrite a" \
        'command that is part of a pipeline, a chain or a redirection, because' \
        'it appends to the end of the command string.' \
        "$(cite "$DOC")"
    fi

    local s8="" a8=""
    if [[ -n "$session_in" ]] && valid_id "$session_in"; then
      s8="${session_in:0:ID_LEN}"
    elif ((spoke)); then
      warn 'the Assisted-by trailer is missing its session field' \
        "$( ((saw_session)) && printf 'the injected session id is unusable: "%s"' "$session_in" \
             || printf 'the hook injected no session id at all' )" \
        'the field is omitted rather than filled with a placeholder, because' \
        'git log cannot tell a placeholder from a real id. The commit is being' \
        'made anyway.' \
        "$(cite "$DOC")"
    fi

    if [[ "$agent_in" == "$MAIN_THREAD" ]]; then
      # The main thread, which the sentinel states outright. Copied rather than
      # truncated or validated: it is a literal, not an id, and putting it
      # through valid_id or ${...:0:ID_LEN} would make the trailer's wording
      # depend on rules written for hex strings of a different length. Silent,
      # because the absence of an agent id here is by design, not a failure.
      a8="$MAIN_THREAD"
    elif [[ -n "$agent_in" ]] && valid_id "$agent_in"; then
      a8="${agent_in:0:ID_LEN}"
    elif ((spoke)); then
      warn 'the Assisted-by trailer is missing its agent field' \
        "$( ((saw_agent)) && printf 'the injected agent id is unusable: "%s"' "$agent_in" \
             || printf 'the hook injected no agent id and no "%s" sentinel' "$MAIN_THREAD" )" \
        'the field is omitted rather than filled with a placeholder, because' \
        'git log cannot tell a placeholder from a real id. The commit is being' \
        'made anyway.' \
        "$(cite "$DOC")"
    fi

    if [[ -n "$tool" ]]; then
      trailer="$TRAILER_KEY: $tool"
      [[ -n "$s8" ]] && trailer+=" session:$s8"
      [[ -n "$a8" ]] && trailer+=" agent:$a8"
    fi
  fi

  if [[ -n "$trailer" ]] && ! git_has_trailer_flag; then
    warn 'no Assisted-by trailer: this git is too old for --trailer' \
      "$(git --version 2>/dev/null || printf 'git --version did not answer')" \
      "git commit --trailer arrived in git $GIT_TRAILER_MAJOR.$GIT_TRAILER_MINOR." \
      'the commit is being made without the trailer rather than refused.' \
      "$(cite "$DOC")"
    trailer=""
  fi

  local -a cmd=(git commit)
  # In front of the caller's arguments, so a trailing `--` still terminates the
  # flags it was written to terminate.
  [[ -n "$trailer" ]] && cmd+=(--trailer "$trailer")
  cmd+=("${argv[@]}")

  if ((print_only)); then
    local out="" a
    for a in "${cmd[@]}"; do out+="$(shell_quote "$a") "; done
    printf '%s\n' "${out% }"
    exit 0
  fi

  command -v git >/dev/null 2>&1 || fail_usage 'git is not installed'
  "${cmd[@]}"
  exit $?
}

main "$@"
