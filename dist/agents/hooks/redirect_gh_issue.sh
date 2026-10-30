#!/usr/bin/env bash
# redirect_gh_issue.sh -- PreToolUse hook (Claude Code matcher "Bash", agy "*",
# Codex "*").
#
# WHAT THIS IS, AND WHAT IT IS NOT
#
# This hook is FOOLPROOFING. It is not a security boundary, it is not a sandbox,
# and it cannot be one. It is handed an arbitrary Bash command string, so
# `bash -c '...'`, `eval`, `G=gh; $G issue create ...`, `xargs`, and a dozen
# other ordinary shell forms reach gh with the hook none the wiser. Deliberate
# evasion is OUT OF SCOPE, and a bypass that needs a command form nobody writes
# by accident is not a bug in this file.
#
# ITS ONLY JOB: notice a direct `gh issue create|new|edit` and point the caller
# at .agents/scripts/gh-issue.sh instead. It does NOT read a title, does not
# extract one, and does not judge one. The rules live in that script, where the
# shell has already parsed the arguments and the title arrives as one element
# of argv.
#
# That is the whole point of the split. Its predecessor, enforce_issue_title.sh,
# hand-parsed the Bash command string to find the title: quoting forms, `-t`
# attached to its value, flags before the subcommand, redirections, process
# substitutions, command substitutions, heredocs. Two rounds of adversarial
# review found 22 then 17 defects, and the last gate failed on a FALSE DENY of
# the repo's own documented recipe, because a heredoc body quoting an example
# title was read as the real title. Writing a shell parser in bash does not
# converge, so this file does not contain one.
#
# MATCHING IS DELIBERATELY CONSERVATIVE. The pattern is anchored at the START of
# the command string -- leading whitespace, leading VAR=value assignments and
# gh's own flags in front of the subcommand, nothing else -- so `gh issue
# create` written inside a heredoc body, inside a quoted example, or in a later
# segment of a `&&` chain is never matched. Forms that are therefore MISSED on
# purpose include a call inside `$(...)` and anything after a `&&`. That
# asymmetry is the design: a missed direct call costs nothing, because the
# script is documented and this hook is only a nudge, while a false deny blocks
# real work and catches no mistake at all.
#
# FLAGS BETWEEN `gh` AND `issue` ARE STEPPED OVER. cobra strips flags before it
# resolves the subcommand, so `gh -R owner/repo issue create --title ...` is a
# working create, and `-R` is the form automation uses to write to a DIFFERENT
# repo -- the call least likely to be read by a human was the one this hook did
# not cover. Stepping over a flag means knowing whether its value is a separate
# word, and the rule is cobra's own, measured against gh 2.98.0 rather than
# guessed:
#   --repo=o/r, -R=o/r, -Ro/r   the value is ATTACHED; one word, nothing follows
#   --repo o/r, -R o/r          the value is the NEXT word, and belongs to it
# Skipping a flag without its value is the dangerous direction: `owner/repo`
# would then be read as the subcommand. So a long `--name` and a lone `-x` are
# both assumed to take a value, even where gh's is a boolean. That assumption
# only ever costs a miss, never a false deny, and gh bears it out both ways:
# `gh -h issue create` really does swallow `issue` as the value of an unknown
# shorthand (gh answers `unknown command "create"`), while `gh --help issue
# create` prints help and creates nothing.
#
# `--` IS NOT STEPPED OVER, deliberately. It terminates cobra's command
# resolution, so `gh -- issue create` finds no subcommand at all (`unknown
# command "issue" for "gh"`) and creates nothing; matching it would deny a
# command that does not exist. .agents/scripts/gh-issue.sh gives `--` no special
# treatment in its own argv parsing and says so -- it can afford to, because by
# then the shell has already decided which program runs.
#
# `gh pr` is left alone entirely: `type(scope):` is still the convention for
# commit messages and PR titles, and nothing about a pull request goes through
# .agents/scripts/gh-issue.sh.
#
# HOOKS MATCHING THE SAME EVENT RUN IN PARALLEL, AND NOTHING SHORT-CIRCUITS.
# Claude Code starts every hook matching an event at once. One hook's deny does
# not stop another in the same array from executing; the results are aggregated
# after all of them have finished, and the most restrictive outcome wins.
#
# The arrangement here rests on that. A redirect hook that refuses a command
# SHAPE, wired alongside a body-routing hook that refuses an INLINE BODY, is
# only safe because neither can mask the other: whichever fires, both verdicts
# are collected, and a deny cannot be swallowed by a hook that ran first and
# allowed. Wire a second hook on that basis, and not on an assumed
# first-verdict-wins ordering -- there is none.
#
# The verdict lives only in the stdout JSON. This hook exits 0 whether it denies
# or stays silent, exactly as the protocol requires, so a test that asserts on
# the exit status would pass an inert hook that prints nothing at all. The
# message is a fixed string with no author-supplied text in it, so it is written
# as literal JSON rather than built by jq or python3 -- there is nothing here
# that could need escaping.
#
# THIS HOOK FAILS CLOSED, so a typo here does not weaken a check -- it stops all
# work. A shell syntax error anywhere in this file makes bash exit 2, which is
# exactly the PreToolUse code for "block", so EVERY Bash call in the session is
# denied until the file parses again; a consumer found this the hard way, with
# an apostrophe dropped into the message string. (Fail-closed is the safer half
# and is kept. The sibling enforce_gh_body_file.sh fails OPEN and silently when
# its library is missing -- issue #6 -- so do not assume a shared convention.)
#
# agy runs the same script from .agents/hooks.json, whose working directory is
# .agents/ -- hence the `./hooks/...` command there. Whether agy acts on Claude
# Code's permissionDecision field is unverified (only script/verify-agents.sh,
# which needs the three CLIs, can answer that), so on agy treat this as advice
# that may not block.
#
# CODEX IS WIRED NOW, AND USED NOT TO BE. This file said for months that Codex
# had no hook mechanism of any kind. That was true when it was measured and it
# is not true now: codex-cli 0.153.2 reads project hooks from <repo>/.codex/,
# and a hook wired there fires -- demonstrated on 2026-09-09, SessionStart and
# PreToolUse both, with a payload whose field names are Claude Code's
# (session_id, cwd, hook_event_name, tool_name "Bash", tool_input.command) and
# whose PreToolUse output schema accepts exactly the hookSpecificOutput /
# permissionDecision "deny" object printed below.
#
# What is measured, stated as measurements:
#   MEASURED   the hook runs, from any depth in the repo, with the payload on
#              stdin; Codex runs the command through a SHELL, from the SESSION's
#              working directory rather than the repo root, and sets no
#              CLAUDE_PROJECT_DIR or equivalent -- hence the
#              "$(git rev-parse --show-toplevel)/..." command in
#              .codex/hooks.json, and hence doc_root()'s git fallback being the
#              branch Codex takes.
#   MEASURED   .codex/ is the DIRECTORY, not .codex/hooks.json the single path:
#              [[hooks.*]] blocks in <repo>/.codex/config.toml are read as
#              project hooks too, and hooks/list returns both layers with
#              source "project". What is measured as NOT read is .agents/ --
#              the identical file placed there yields no entry. This file is
#              wired from hooks.json only because that is what this harness
#              ships; a consumer who keeps their hooks in .codex/config.toml is
#              not doing it wrong.
#   MEASURED   two trust gates, both silent under `codex exec`: the repo must be
#              a trusted project in ~/.codex/config.toml -- named by its exact
#              root path, trust does not descend from a parent entry -- and the
#              hook itself must have been reviewed. Fail either and the hook
#              does not run and nothing is printed. Outside `codex exec` the
#              trust gate is loud: the app-server and the TUI print an ERROR
#              naming the untrusted .codex folder.
#   MEASURED   the deny is ACTED ON. This block said "NOT MEASURED" until
#              2026-09-09, when a run watched it: with both gates cleared,
#              `codex exec` on a `gh issue create` printed
#              "hook: PreToolUse Blocked" and "Command blocked by PreToolUse
#              hook: ...", from the repo root and from a subdirectory, and a
#              `gh` stub first on PATH recorded zero invocations -- the command
#              did not run. agy's standing is unchanged: still unverified.
#
# Which is why the split still matters, and matters more than before: the rules
# live in .agents/scripts/gh-issue.sh, which every agent can call and which no
# trust gate can switch off. All three agents now also get this nudge, on three
# different conditions.
#
# Driven by script/ci/ci.sh check_redirect_hook with real stdin payloads.

set -uo pipefail

# Reading the payload needs a JSON implementation. If neither is present the
# hook stays silent: it can only ever cost a redirect message, and the rules
# themselves do not depend on it. (Its predecessor announced this instead,
# because there the silence meant the rules had stopped being applied at all.)
read_command() {                  # stdin = the hook payload
  if command -v jq >/dev/null 2>&1; then
    jq -r '.tool_input.command // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
try:
    sys.stdout.write(json.load(sys.stdin).get("tool_input", {}).get("command", "") or "")
except Exception:
    pass' 2>/dev/null
  fi
}

# Leading `VAR=value` assignments are ordinary in front of a command
# (`GH_HOST=github.com gh issue create ...`), so they are stepped over. The
# value is matched without whitespace, which keeps the anchor at the start of
# the command: a quoted assignment carrying spaces is simply not matched, which
# costs a redirect and nothing else.
readonly ASSIGN='[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+'
# `gh`, or any path ending in `/gh`. Not `gh-issue.sh` and not
# `.agents/scripts/gh-issue.sh`: the whitespace after the word is part of the
# pattern, and `.agents/scripts/gh` is followed by `-issue.sh`, not a space.
readonly GH='(gh|[^[:space:]]*/gh)'
# Flags in front of the subcommand, stepped over one at a time. Split by where
# the VALUE is, because getting that wrong reads a value as the subcommand.
#
# ATTACHED: after an `=` (`--repo=o/r`, `-R=o/r`), or straight onto a shorthand
# (`-Ro/r` -- pflag's own form, the same one gh-issue.sh splits back apart in
# its argv). One word, and the word after it is not its value.
readonly FLAG_ATTACHED='(--?[A-Za-z][^[:space:]=]*=[^[:space:]]*|-[A-Za-z][^[:space:]=]+)[[:space:]]+'
# SEPARATE: a long `--name`, or a shorthand alone. The next word is consumed as
# its value. It has to look like a value -- not another flag -- so a run of
# flags cannot silently eat the word after the last one.
readonly FLAG_VALUED='(--[A-Za-z][^[:space:]=]*|-[A-Za-z])[[:space:]]+[^-[:space:]][^[:space:]]*[[:space:]]+'
# Both alternatives require a letter after the dashes, which is what keeps `--`
# out: it ends cobra's search for a subcommand rather than hiding one.
readonly FLAGS="($FLAG_ATTACHED|$FLAG_VALUED)"
readonly DIRECT="^[[:space:]]*($ASSIGN)*${GH}[[:space:]]+($FLAGS)*issue[[:space:]]+(create|new|edit)([[:space:]]|$)"

# READ-ONLY FORMS ARE EXEMPT, AND THE ONLY ONE IS A HELP LOOKUP.
# `gh issue create --help` and `gh issue edit --help` create and edit nothing:
# cobra prints the flag list and exits before the command body runs. Denying
# them blocked a harmless lookup and taught the reader nothing, since the
# script's own --help does not list gh's flags.
#
# The exemption is deliberately NARROW: the help flag has to be the first word
# after the subcommand, or the first after a single bare argument (the issue
# number or URL that `edit` takes). That is where a person types it, and it is
# the only position in which the word provably belongs to gh rather than to a
# flag in front of it -- `gh issue create --title --help` files an issue
# titled "--help", so a rule of "the string --help appears somewhere" would
# exempt a real create. Anchored at the front, `--help` cannot be a value,
# because there is no preceding flag for it to be the value of.
#
# Nothing else is exempted. `--web` was considered and rejected: it opens a
# prefilled form in a browser, which is a create with a longer path, not a
# read. The test is "provably mutates nothing", not "usually harmless".
readonly BARE_ARG='[^-][^[:space:]]*[[:space:]]+'
readonly HELP="^[[:space:]]*($ASSIGN)*${GH}[[:space:]]+($FLAGS)*issue[[:space:]]+(create|new|edit)[[:space:]]+($BARE_ARG)?(--help|-h)([[:space:]]|$)"

# `new` is gh's own alias for `create` (gh 2.98.0, alongside `ls` for `list`;
# `edit` has no alias), so it is named here too -- it is a form a person types.
#
# THE PATH IN THE MESSAGE IS THE DELIVERED ONE. This hook is shipped, and both
# dist config files wire it, so its message is read in repos that are not this
# one. .agents/scripts/gh-issue.sh is where init.sh puts the script in every
# install; naming script/gh-issue.sh -- a path only this repo has -- told a
# consumer to run something they had never been given.
#
# THE TEXT IS READ FROM A QUOTED HEREDOC, NOT A SINGLE-QUOTED STRING. It has no
# apostrophe in it today, but prose acquires one the moment somebody writes
# "doesn't", and inside '...' that ends the string and leaves the file
# unparseable -- which, per the fail-closed note above, denies every Bash call
# in the session rather than just losing this message. `<<'EOF'` interpolates
# nothing and terminates on its own line, so no character in the body can end
# it. The trailing newline the heredoc adds is stripped, so the emitted text is
# byte for byte what it was.
IFS= read -r -d '' MESSAGE <<'GH_ISSUE_MESSAGE'
Use .agents/scripts/gh-issue.sh instead of calling gh issue create/edit directly.

  .agents/scripts/gh-issue.sh create --title "scope: what is broken" \
      --body-file /tmp/body.md --label enhancement --label needs-triage
  .agents/scripts/gh-issue.sh edit 12 --title "scope: a better statement of the problem"

The script reads the title from its own argv, so it checks the real title and
the real body: the scope prefix, the 80-character limit, the body sections and
the label roles. A body has to carry "## Context" and "## Out of scope";
"## Problem", "## Proposal" and "## Acceptance criteria" are optional, because a
small issue may collapse Proposal into Problem and drop Acceptance. Presence and
order are separate questions: whichever sections are present appear in the
canonical order -- Context, Problem, Proposal, Acceptance criteria, Out of
scope. It always passes the body to gh as --body-file. Add
--dry-run (or GH_ISSUE_DRY_RUN=1) to see the exact gh command without running
it. It works for all three agents, and unlike this hook it does not depend on
any agent having its hooks enabled and trusted.

gh pr is unaffected.
GH_ISSUE_MESSAGE
MESSAGE="${MESSAGE%$'\n'}"
readonly MESSAGE

# THE MESSAGE HAS TO STAND ON ITS OWN, BECAUSE dist/ DOES NOT SHIP doc/.
# This hook is delivered into repos that have no doc/agents/issue-tracker.md,
# and a message that ends "see <file>" for a file the reader was never given is
# worse than one that ends without it: it reads as a missing install. So the
# message above carries what the reader has to know -- run the script, and the
# script names the rule it applies -- and the citation is appended only where
# the document actually is. The rule is never carried by the pointer alone.
readonly CITATION='See doc/agents/issue-tracker.md, "Issue titles".'
readonly CITED='doc/agents/issue-tracker.md'

# Repo-relative, so it is resolved against the repository root rather than
# whatever directory the agent happened to be in. CLAUDE_PROJECT_DIR is set by
# Claude Code; git answers for agy, for Codex (which sets no such variable and
# starts the hook in the session's directory) and for a hand-run; $PWD is the
# last resort.
doc_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -d "${CLAUDE_PROJECT_DIR}" ]]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  local root=""
  command -v git >/dev/null 2>&1 && root="$(git rev-parse --show-toplevel 2>/dev/null)"
  printf '%s' "${root:-$PWD}"
}

message() {
  if [[ -f "$(doc_root)/$CITED" ]]; then
    printf '%s\n\n%s' "$MESSAGE" "$CITATION"
  else
    printf '%s' "$MESSAGE"
  fi
}

main() {
  local cmd
  cmd="$(read_command)"
  [[ -z "$cmd" ]] && return 0
  [[ "$cmd" =~ $DIRECT ]] || return 0
  # A help lookup runs no command body, so there is nothing to redirect.
  [[ "$cmd" =~ $HELP ]] && return 0

  # Fixed text, no interpolation: the only variable part is the newline
  # escaping, done once here.
  local text; text="$(message)"
  local json_message="${text//\\/\\\\}"
  json_message="${json_message//\"/\\\"}"
  json_message="${json_message//$'\n'/\\n}"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$json_message" "$json_message"
  return 0
}

main "$@"
