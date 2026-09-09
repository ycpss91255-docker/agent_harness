#!/usr/bin/env bash
# redirect_gh_issue.sh -- PreToolUse hook (Claude Code matcher "Bash", agy "*").
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
# the command string -- leading whitespace and leading VAR=value assignments
# only -- so `gh issue create` written inside a heredoc body, inside a quoted
# example, or in a later segment of a `&&` chain is never matched. Forms that
# are therefore MISSED on purpose include `gh -R owner/repo issue create`, a
# call inside `$(...)`, and anything after a `&&`. That asymmetry is the design:
# a missed direct call costs nothing, because the script is documented and this
# hook is only a nudge, while a false deny blocks real work and catches no
# mistake at all.
#
# `gh pr` is left alone entirely: `type(scope):` is still the convention for
# commit messages and PR titles, and nothing about a pull request goes through
# .agents/scripts/gh-issue.sh.
#
# The verdict lives only in the stdout JSON. This hook exits 0 whether it denies
# or stays silent, exactly as the protocol requires, so a test that asserts on
# the exit status would pass an inert hook that prints nothing at all. The
# message is a fixed string with no author-supplied text in it, so it is written
# as literal JSON rather than built by jq or python3 -- there is nothing here
# that could need escaping.
#
# Codex has no hook mechanism of any kind, so nothing is wired for it. Unlike
# the arrangement this replaces, that is no longer a gap in the rules: Codex
# calls .agents/scripts/gh-issue.sh like everyone else, and the script is where
# the rules are. All three agents get the checks; two of the three also get this nudge.
#
# agy runs the same script from .agents/hooks.json, whose working directory is
# .agents/ -- hence the `./hooks/...` command there. Whether agy acts on Claude
# Code's permissionDecision field is unverified (only script/verify-agents.sh,
# which needs the three CLIs, can answer that), so on agy treat this as advice
# that may not block.
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
readonly DIRECT="^[[:space:]]*($ASSIGN)*${GH}[[:space:]]+issue[[:space:]]+(create|new|edit)([[:space:]]|$)"

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
readonly HELP="^[[:space:]]*($ASSIGN)*${GH}[[:space:]]+issue[[:space:]]+(create|new|edit)[[:space:]]+($BARE_ARG)?(--help|-h)([[:space:]]|$)"

# `new` is gh's own alias for `create` (gh 2.98.0, alongside `ls` for `list`;
# `edit` has no alias), so it is named here too -- it is a form a person types.
#
# THE PATH IN THE MESSAGE IS THE DELIVERED ONE. This hook is shipped, and both
# dist config files wire it, so its message is read in repos that are not this
# one. .agents/scripts/gh-issue.sh is where init.sh puts the script in every
# install; naming script/gh-issue.sh -- a path only this repo has -- told a
# consumer to run something they had never been given.
readonly MESSAGE='Use .agents/scripts/gh-issue.sh instead of calling gh issue create/edit directly.

  .agents/scripts/gh-issue.sh create --title "scope: what is broken" \
      --body-file /tmp/body.md --label enhancement --label needs-triage
  .agents/scripts/gh-issue.sh edit 12 --title "scope: a better statement of the problem"

The script reads the title from its own argv, so it checks the real title and
the real body: the scope prefix, the 80-character limit, the five body sections
and the label roles. It always passes the body to gh as --body-file. Add
--dry-run (or GH_ISSUE_DRY_RUN=1) to see the exact gh command without running
it. It works for all three agents, including Codex, which has no hooks.

gh pr is unaffected.'

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
# Claude Code; git answers for agy and for a hand-run; $PWD is the last resort.
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
