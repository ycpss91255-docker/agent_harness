#!/usr/bin/env bash
# gh-issue.sh -- the entry point for filing and editing issues.
#
#   .agents/scripts/gh-issue.sh create \
#       --title "hooks: the redirect fires on a heredoc" \
#       --body-file /tmp/body.md --label enhancement --label needs-triage
#   .agents/scripts/gh-issue.sh edit 12 \
#       --title "hooks: a better statement of the problem"
#
# WHERE THIS LIVES, AND WHY
#
# The file itself is dist/agents/scripts/gh-issue.sh, and init.sh links it to
# .agents/scripts/gh-issue.sh in every repo that installs the harness. That is
# the path to name anywhere, because it is the only one that is true in a
# consumer's repo as well as in this one. It used to live in script/, which
# dist/ does not ship, while the redirect hook that names it IS shipped and
# wired in both config files -- so a fresh install got a hook telling its author
# to run a script the install had not delivered.
#
# This repo also keeps script/gh-issue.sh as a symlink to the file, so its own
# documented invocation path still works.
#
# WHY A SCRIPT AND NOT A HOOK
#
# These rules used to live in a PreToolUse hook that was handed the whole Bash
# command string and had to find the title inside it. That means hand-writing a
# shell parser in bash: quoting forms, `-t` attached to its value, flags before
# the subcommand, redirections, process substitutions, command substitutions,
# heredocs. Two rounds of adversarial review turned up 22 then 17 defects, and
# the last gate failed on a FALSE DENY of this document's own recipe, because a
# heredoc body quoting an example title was read as the real title. Hand-parsing
# the shell in bash does not converge.
#
# This inverts it. The shell has already parsed the arguments before this script
# runs, so the title arrives as one element of argv -- not as a substring of a
# command line. There is nothing to tokenise and nothing to guess, and a body
# that quotes an example title cannot be mistaken for a title. The entire defect
# class disappears.
#
# The pattern is general: when an operation is error-prone enough to need
# rules, the hook does not try to validate the ad-hoc command. It denies the
# ad-hoc form outright and forces the caller through a script that encodes the
# rules -- the hook only has to say "not that way, this way", and the script
# receives real arguments it can actually check.
#
# ALL THREE AGENTS CAN CALL THIS, UNCONDITIONALLY. That was once a claim about
# Codex having no hooks at all; it no longer is. Codex 0.153.2 does have project
# hooks, read from <repo>/.codex/ (demonstrated 2026-09-09), and the redirect
# hook is wired for it. The reason the rules still live here is narrower and
# sturdier: every hook path is conditional on something the repo does not
# control -- Claude Code's and agy's on a policy file the consumer owns and
# init.sh will not edit, Codex's on two trust gates that a fresh clone fails
# silently. A script is the one carrier with no such gate on it.
#
# WHAT IS CHECKED (authority: doc/agents/issue-tracker.md, "Issue titles", and
# doc/agents/triage-labels.md)
#
#   title   rule 1  a bare `scope: ` prefix of one or two words. The
#                   Conventional-Commits `type(scope):` form is reserved for
#                   commits and PR titles and is refused here.
#           rule 3  at most 80 characters, counted in CHARACTERS, not bytes.
#           rule 4  undecidedness belongs in the needs-decision label. This is a
#                   heuristic, so it warns and never refuses: "decision" is a
#                   legitimate word in a problem statement, and a check that
#                   blocked it would only train the author around it.
#           Rule 2 -- state the problem, not the fix -- is not machine-checkable
#           and is deliberately not attempted.
#   body    "## Context" and "## Out of scope" are required. "## Problem",
#           "## Proposal" and "## Acceptance criteria" are optional, and
#           whichever of them are present appear in the canonical order:
#           Context, Problem, Proposal, Acceptance criteria, Out of scope.
#           gh-artifact-format section 2: "Small issues (one-line bug, trivial
#           doc tweak) may collapse Proposal into Problem and drop Acceptance.
#           Context and Out of scope stay." Requiring all five refused a small
#           issue the convention permits, which is a false deny -- the worst
#           class of defect this script has.
#   labels  exactly one category (create) or at most one (edit), and at most one
#           state. `backlog` is orthogonal and is not a state.
#
# A violation REFUSES: it names the rule, says how to fix it, and exits
# non-zero. Nothing is silently corrected -- a script that rewrote the author's
# title would teach nobody the convention and would file something the author
# never wrote.
#
# THE REFUSAL CARRIES THE RULE, NOT A POINTER TO IT. dist/ ships this script
# and does not ship doc/, so in a consumer's repo the documents named below do
# not exist. Every refusal therefore states the rule and the fix in its own
# words, and the "see <document>" line is appended only where that document is
# actually present -- naming a file the reader was never given reads as a
# broken install and tells them nothing. See cite() below.
#
# The body always reaches gh as `--body-file`, never inline, so no body text
# ever has to survive a second trip through the shell.
#
# DRY RUN: `--dry-run`, or GH_ISSUE_DRY_RUN=1 in the environment. Validates
# everything, prints the exact gh command it would run, exits 0, and touches
# GitHub not at all.
#
# THE DRY RUN IS A CONVENIENCE FOR A HUMAN, AND NOTHING MAY DEPEND ON IT FOR
# SAFETY. It is a flag honoured by this script, so it is worth exactly as much
# as this script is correct -- and this script has had defects on that path.
# When it did, script/ci/ci.sh was relying on it to stay off the network, and
# the suite filed three real issues against this repo. The suite now installs
# its own `gh` first on PATH instead: within that check there is no real gh to
# reach, so no defect here and no future edit to this file can get out. A test
# suite is kept off the network by its ENVIRONMENT, never by a flag the code
# under test is trusted to honour.
#
# Driven by script/ci/ci.sh check_gh_issue.

set -uo pipefail

readonly MAX_LEN=80
readonly DOC='doc/agents/issue-tracker.md'
readonly LABEL_DOC='doc/agents/triage-labels.md'

# Repo-relative, so the documents are looked for at the repository root rather
# than in whatever directory the agent happened to be standing in.
doc_root() {
  local root=""
  command -v git >/dev/null 2>&1 && root="$(git rev-parse --show-toplevel 2>/dev/null)"
  printf '%s' "${root:-$PWD}"
}

# The citation line for a document, or nothing at all if this repo does not
# have it. Every caller passes the result as one more line to refuse(), warn()
# or fail_usage(), all of which drop an empty line -- so the message loses its
# last line and keeps the rule.
cite() {                          # cite <document> [section]
  [[ -f "$(doc_root)/$1" ]] || return 0
  if [[ -n "${2:-}" ]]; then
    printf 'see %s, "%s"' "$1" "$2"
  else
    printf 'see %s' "$1"
  fi
}

# The body shape: the canonical order the sections appear in when they appear.
readonly SECTIONS=(
  '## Context'
  '## Problem'
  '## Proposal'
  '## Acceptance criteria'
  '## Out of scope'
)

# ...and the two that a body always carries. The rest are optional, because the
# convention says so: a small issue may collapse Proposal into Problem and drop
# Acceptance, while Context and Out of scope stay. Presence and order are
# separate questions here -- an absent optional section is legal, an optional
# section in the wrong place is not.
readonly REQUIRED_SECTIONS=(
  '## Context'
  '## Out of scope'
)

# doc/agents/triage-labels.md: one category role, at most one state role.
# `backlog` is in neither list on purpose -- it is orthogonal to the state
# machine, so it may travel with any state. Labels in neither list (wayfinder:*,
# Dependabot's own) are passed through unjudged; this script owns the two roles
# the triage vocabulary defines and nothing else.
readonly CATEGORY_LABELS=(bug documentation enhancement)
readonly STATE_LABELS=(needs-triage needs-info needs-decision ready-for-agent
                       ready-for-human wontfix)

usage() {
  cat >&2 <<'USAGE'
usage:
  gh-issue.sh create --title TITLE (--body-file PATH | --body TEXT)
                     [--label NAME]... [gh flags...]
  gh-issue.sh edit NUMBER [--title TITLE] [--body-file PATH | --body TEXT]
                     [--add-label NAME]... [--remove-label NAME]... [gh flags...]

  --dry-run        print the gh command that would run, change nothing
                   (GH_ISSUE_DRY_RUN=1 does the same)
  -h, --help       this text

Any flag not listed above is forwarded to gh untouched (--repo, --assignee,
--milestone, ...).
USAGE
  local c; c="$(cite "$DOC")"
  [[ -n "$c" ]] && printf '%s\n' "$c" >&2
  return 0
}

# Exit codes: 1 a convention violation, 2 a usage error. Both are non-zero, so a
# caller that only tests success cannot tell them apart -- which is the point.
refuse() {                        # refuse <rule> <line>...
  local rule="$1"; shift
  printf 'gh-issue.sh: refused -- %s\n' "$rule" >&2
  local line
  # An empty line is a citation that was dropped because this repo does not
  # carry the document; printing it would leave a blank indented line where a
  # reader expects the pointer.
  for line in "$@"; do [[ -n "$line" ]] && printf '  %s\n' "$line" >&2; done
  exit 1
}

fail_usage() {                    # fail_usage <line>...
  local line
  for line in "$@"; do [[ -n "$line" ]] && printf 'gh-issue.sh: %s\n' "$line" >&2; done
  usage
  exit 2
}

warn() {                          # warn <headline> <line>...
  printf 'gh-issue.sh: %s\n' "$1" >&2
  shift
  local line
  for line in "$@"; do [[ -n "$line" ]] && printf '  %s\n' "$line" >&2; done
}

# An inline --body is written to a temporary file and passed as --body-file, so
# the file has to outlive every refusal path as well as the successful one.
TMP_BODY=""
cleanup() {
  [[ -n "$TMP_BODY" ]] && rm -f -- "$TMP_BODY"
  return 0
}
trap cleanup EXIT

# Characters, not bytes. bash's ${#s} counts characters only in a UTF-8 locale,
# and this runs in whatever environment the agent was started with -- a
# container or a CI runner routinely has no LANG at all, where ${#s} silently
# becomes a byte count and an 80-character title is refused as "152 characters".
# python3 and jq both count codepoints regardless of locale (PYTHONUTF8 pins
# python3's argv decoding to UTF-8).
title_length() {                  # title_length <title>
  local n=""
  if command -v python3 >/dev/null 2>&1; then
    n="$(PYTHONUTF8=1 python3 -c 'import sys
print(len(sys.argv[1]))' "$1" 2>/dev/null)"
  elif command -v jq >/dev/null 2>&1; then
    n="$(jq -rn --arg t "$1" '$t | length' 2>/dev/null)"
  fi
  if [[ "$n" =~ ^[0-9]+$ ]]; then
    printf '%s' "$n"
    return
  fi

  # Neither available, or one of them failed. `${#s}` alone is NOT a fallback:
  # outside a UTF-8 locale it counts bytes, and a legal 79-character title made
  # of two-byte characters is then refused as "150 characters" -- a refusal of
  # something the document permits, which is the worst outcome this script has.
  #
  # So the count is made locale-independent instead. A two-byte probe says which
  # semantics ${#s} is using here: 1 means characters (a UTF-8 locale, already
  # right), 2 means bytes. Under byte semantics the UTF-8 continuation bytes
  # (0x80-0xBF) are dropped -- a continuation byte is never the first byte of a
  # character, so what is left is one byte per character. Input that is not
  # valid UTF-8 counts high, which is the conservative direction.
  local probe=$'\xc3\xa9'
  if ((${#probe} == 1)); then
    printf '%s' "${#1}"
  else
    local lead="${1//[$'\x80'-$'\xbf']/}"
    printf '%s' "${#lead}"
  fi
}

# Order matters. `feat(hooks): x` also has no bare scope prefix, and naming the
# Conventional-Commits form tells the author what to change; reporting "no scope
# prefix" for it would send them looking for the wrong thing.
check_title() {                   # check_title <title>
  local title="$1" len

  # A title is one line. Checked first and on its own, because every rule below
  # is anchored to the whole string: without this, "hooks: fine" followed by a
  # newline and anything at all would be reported as having no scope prefix,
  # sending the author to look at a first line that is already correct.
  if [[ "$title" == *$'\n'* ]]; then
    refuse 'rule 1, bare scope prefix' \
      "title: \"$title\"" \
      'an issue title is a single line; this one contains a line break.' \
      'put the detail in the body, which is where the sections live.' \
      "$(cite "$DOC" 'Issue titles')"
  fi

  if [[ "$title" =~ ^[a-z]+\(([^\)]*)\):[[:space:]]+(.*)$ ]]; then
    # Hand back the rewritten title, not just the rule: the scope and the
    # subject are both already in what the author typed.
    local suggestion="${BASH_REMATCH[1]}: ${BASH_REMATCH[2]}"
    [[ -n "${BASH_REMATCH[1]}" ]] || suggestion="<scope>: ${BASH_REMATCH[2]}"
    refuse 'rule 1, bare scope prefix' \
      "title: \"$title\"" \
      'this is the Conventional-Commits type(scope): form, which is reserved' \
      'for commit messages and PR titles. An issue title takes a bare scope' \
      'prefix instead: the type restates the category label the issue already' \
      'carries, while the scope is information no label records.' \
      "try: \"$suggestion\"" \
      "$(cite "$DOC" 'Issue titles')"
  fi

  len="$(title_length "$title")"
  if ((len > MAX_LEN)); then
    refuse 'rule 3, at most 80 characters' \
      "title: \"$title\"" \
      "that is $len characters; the limit is $MAX_LEN." \
      'cut it down to the problem itself.' \
      "$(cite "$DOC" 'Issue titles')"
  fi

  # One or two words, which is what the document says: "issue tracker: citations
  # go stale" is as legal as "hooks: citations go stale". Requiring a single word
  # refuses a title the document explicitly permits.
  # Anchored at BOTH ends. Anchored only at the start, the rule is satisfied by
  # any string that merely BEGINS with a scope prefix, so everything after the
  # first few words goes unread -- which is how a multi-line title used to pass
  # on the strength of its first line alone. [[:blank:]] rather than
  # [[:space:]], and [^[:cntrl:]] for the description, so a newline cannot
  # satisfy any part of the pattern.
  if ! [[ "$title" =~ ^[a-z][a-z0-9-]*([[:blank:]][a-z0-9-]+)?:[[:blank:]]+[^[:space:]][^[:cntrl:]]*$ ]]; then
    refuse 'rule 1, bare scope prefix' \
      "title: \"$title\"" \
      'an issue title is "scope: description", where the scope is one or two' \
      'lower-case words naming the part of the repo the issue touches:' \
      'skill, skills, hooks, prd, labels, repo, docs, issue tracker.' \
      "$(cite "$DOC" 'Issue titles')"
  fi

  # Rule 4 is a heuristic and must never block.
  local lower="${title,,}"
  if [[ "$lower" =~ (^|[^a-z])(decide|decision|should[[:space:]]+we)([^a-z]|$) ]]; then
    warn 'warning (not blocking) -- rule 4, undecidedness goes in the label' \
      "title: \"$title\"" \
      'this reads as undecided. If the deliverable is a decision, that belongs' \
      'in the needs-decision label, and the title states the open problem.' \
      "$(cite "$DOC" 'Issue titles')"
  fi
}

# Two questions, asked separately, because the answers are not the same shape:
# are the REQUIRED sections there, and are the sections that ARE there in the
# canonical order? A single forward cursor cannot ask them apart -- it reports a
# legally absent optional section as "missing", which is how a small issue the
# convention permits used to be refused.
#
# So the scan records which headings it saw and where, an out-of-order heading
# is reported as itself rather than as the one that was expected in its place,
# and only the required two are checked for presence afterwards. A heading that
# repeats is the same section written twice, not a second one, and is ignored --
# the previous scan ignored it too, and refusing it names nothing an author can
# act on.
check_body() {                    # check_body <path>
  local file="$1"
  # -r alone is not the test. A directory passes it, and the read loop below
  # then dies on the redirect with "Is a directory" followed by an unbound
  # variable -- a bash traceback where a usage error belongs. Each case is named
  # separately because "no such file" and "that is a directory" send the author
  # to different places.
  if [[ ! -e "$file" ]]; then
    fail_usage "no such body file: $file"
  elif [[ -d "$file" ]]; then
    fail_usage "body file is a directory: $file" \
      '--body-file takes the path of the file holding the body.'
  elif [[ ! -f "$file" ]]; then
    fail_usage "body file is not a regular file: $file"
  elif [[ ! -r "$file" ]]; then
    fail_usage "cannot read body file: $file"
  fi

  local n=${#SECTIONS[@]}
  local i k line="" last=-1
  local -a seen=()
  for ((i = 0; i < n; i++)); do seen[i]=0; done

  # A heading inside a fenced code block is a QUOTATION of the convention, not a
  # section of this body -- and quoting the section list is ordinary usage here,
  # because the issues this repo files are routinely about the format itself.
  # A scan with no fence state got it wrong in BOTH directions: a legal body
  # that quoted the list was refused as "sections out of order", and a body
  # whose only Context and Out of scope sat inside a fence was accepted as if it
  # carried them.
  #
  # Both markers, because Markdown has both -- and a body that quotes ``` has to
  # fence the quotation with ~~~, so treating only one of them as a fence is the
  # same bug again. The run length is tracked rather than assumed to be three:
  # a longer run is exactly what a fence containing a shorter one is opened
  # with, and a closer only closes a fence of its own character that is at least
  # as long. An opening fence may carry a language tag; a closing one may not,
  # which is why ```markdown opens a block rather than closing one.
  local fence_re='^(`{3,}|~{3,})(.*)$'
  local fence_char="" fence_len=0 bare marker rest
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trailing whitespace after a heading is invisible in a diff and must not
    # decide whether the body is valid.
    line="${line%"${line##*[![:space:]]}"}"
    bare="${line#"${line%%[![:space:]]*}"}"
    if [[ "$bare" =~ $fence_re ]]; then
      marker="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
      if [[ -z "$fence_char" ]]; then
        # A backtick fence's info string may not itself contain a backtick, so
        # a line of prose like ```gh``` opens nothing.
        if [[ "${marker:0:1}" != '`' || "$rest" != *'`'* ]]; then
          fence_char="${marker:0:1}"
          fence_len=${#marker}
        fi
      elif [[ "${marker:0:1}" == "$fence_char" ]] \
        && ((${#marker} >= fence_len)) \
        && [[ -z "${rest//[[:space:]]/}" ]]; then
        fence_char=""
        fence_len=0
      fi
      continue                    # a fence line is never a heading either
    fi
    # Inside a fence, and an unclosed fence runs to the end of the body: the
    # lines are code, and code is not this body's shape.
    [[ -n "$fence_char" ]] && continue
    for ((k = 0; k < n; k++)); do
      [[ "$line" == "${SECTIONS[k]}" ]] || continue
      ((seen[k])) && break        # the same heading again; one section, not two
      if ((k < last)); then
        refuse 'body shape, sections out of order' \
          "body file: $file" \
          "\"${SECTIONS[k]}\" comes after \"${SECTIONS[last]}\"" \
          'the sections that are present appear in this order:' \
          "  ${SECTIONS[0]}          (required)" \
          "  ${SECTIONS[1]}" \
          "  ${SECTIONS[2]}" \
          "  ${SECTIONS[3]}" \
          "  ${SECTIONS[4]}    (required)" \
          "$(cite "$DOC")"
      fi
      seen[k]=1
      last=$k
      break
    done
  done < "$file"

  local want
  for want in "${REQUIRED_SECTIONS[@]}"; do
    for ((k = 0; k < n; k++)); do
      [[ "${SECTIONS[k]}" == "$want" ]] && break
    done
    ((seen[k])) && continue
    refuse 'body shape, Context and Out of scope are required' \
      "body file: $file" \
      "missing: $want" \
      'a body always carries these two:' \
      "  ${REQUIRED_SECTIONS[0]}" \
      "  ${REQUIRED_SECTIONS[1]}" \
      'the other three are optional -- a small issue may collapse Proposal into' \
      'Problem and drop Acceptance -- and whichever are present appear in this' \
      'order:' \
      "  ${SECTIONS[0]}" \
      "  ${SECTIONS[1]}" \
      "  ${SECTIONS[2]}" \
      "  ${SECTIONS[3]}" \
      "  ${SECTIONS[4]}" \
      "$(cite "$DOC")"
  done
}

# CASE-INSENSITIVELY, because GitHub is. A label name is matched without regard
# to case there, so `--label BUG` is the repo's own `bug` and has to be judged as
# one. Compared exactly, `BUG` was a name in neither CATEGORY_LABELS nor
# STATE_LABELS: `--label BUG --label enhancement` was counted as ONE category,
# accepted, and filed as two -- the combination these rules exist to prevent.
#
# This is only ever about what a caller types. The repo's own labels are the
# lower-case canonical names in the two lists below, which is also why the name
# is forwarded to gh exactly as it was typed rather than rewritten here: gh
# resolves the case itself, and this script does not silently correct anybody.
in_list() {                       # in_list <needle> <haystack...>
  local needle="${1,,}"; shift
  local item
  for item in "$@"; do
    [[ "${item,,}" == "$needle" ]] && return 0
  done
  return 1
}

check_labels() {                  # check_labels <require-category:0|1> <label...>
  local require="$1"; shift
  local -a cats=() states=()
  local label
  for label in "$@"; do
    # Counted as a SET, not as a list. `--label bug --label bug` is one label:
    # gh de-duplicates them, the issue ends up carrying exactly one, and
    # refusing it as "two category labels: bug bug" names a conflict that does
    # not exist and leaves the author nothing they can change.
    if in_list "$label" "${CATEGORY_LABELS[@]}" && ! in_list "$label" "${cats[@]}"; then
      cats+=("$label")
    fi
    if in_list "$label" "${STATE_LABELS[@]}" && ! in_list "$label" "${states[@]}"; then
      states+=("$label")
    fi
  done

  if ((require)) && ((${#cats[@]} == 0)); then
    refuse 'labels, exactly one category' \
      'a new issue carries exactly one category label:' \
      "  ${CATEGORY_LABELS[*]}" \
      "$(cite "$LABEL_DOC" 'Category labels')"
  fi
  if ((${#cats[@]} > 1)); then
    refuse 'labels, exactly one category' \
      "two category labels: ${cats[*]}" \
      'an issue carries exactly one of them.' \
      "$(cite "$LABEL_DOC" 'Category labels')"
  fi
  if ((${#states[@]} > 1)); then
    refuse 'labels, at most one state' \
      "two state labels: ${states[*]}" \
      'an issue is in one state at a time. backlog is orthogonal and is not a' \
      'state, so it may travel with any of them.' \
      "$(cite "$LABEL_DOC" 'Labels that are NOT triage states')"
  fi
}

# Quote a single argument the way a person would have to type it, so that the
# dry-run line can be pasted into a shell and mean the same thing.
shell_quote() {                   # shell_quote <arg>
  local s="$1"
  if [[ -n "$s" && "$s" =~ ^[A-Za-z0-9_@%+=:,./-]+$ ]]; then
    printf '%s' "$s"
  else
    printf "'%s'" "${s//\'/\'\\\'\'}"
  fi
}

main() {
  local dry="${GH_ISSUE_DRY_RUN:-0}"
  # --dry-run reads naturally on either side of the subcommand, and a flag that
  # only works in one position is a flag somebody runs for real by accident.
  while [[ "${1:-}" == --dry-run ]]; do dry=1; shift; done

  local sub="${1:-}"
  case "$sub" in
    create|edit) shift ;;
    -h|--help)   usage; exit 0 ;;
    '')          fail_usage 'no subcommand' ;;
    *)           fail_usage "unknown subcommand: $sub" ;;
  esac

  local number="" title="" title_set=0 body_file="" body_text="" body_text_set=0
  local -a add_labels=() label_argv=() passthrough=()

  if [[ "$sub" == edit ]]; then
    # The target is the first argument, always. Digging it out of a mixed
    # argument list would mean guessing which flags take a value -- the guessing
    # this script exists to avoid.
    #
    # gh addresses an issue by number OR by URL, and the redirect hook denies
    # `gh issue edit <url>` on its shape like any other direct call. While this
    # only took a number there was no way through either half: the hook sent the
    # author here and this refused them, for a form gh itself accepts. The URL
    # is forwarded to gh verbatim -- it is gh's own address format, and nothing
    # here needs the number out of it.
    number="${1:-}"
    if ! [[ "$number" =~ ^[0-9]+$ || "$number" =~ ^https?://[^/[:space:]]+/[^[:space:]]+/issues/[0-9]+$ ]]; then
      fail_usage 'edit takes the issue number or its URL as the first argument' \
        "got: \"$number\"" \
        'e.g. 12, or https://github.com/owner/repo/issues/12'
    fi
    shift
  fi

  while (($#)); do
    # gh is a pflag program, so a shorthand may carry its value ATTACHED:
    # `-lbug`, `-thooks: x`, `-F/tmp/b.md`, and the `-l=bug` form too. None of
    # those match the case below, so each one used to land in passthrough and
    # reach gh unread -- a title never checked, a body never checked, and label
    # combinations the rules forbid filed anyway. Splitting the value back off
    # first means an attached value is judged exactly like a detached one.
    # Only the four shorthands this script judges are pulled out; every other
    # shorthand is gh's business and is forwarded byte for byte.
    # The `=` is stripped afterwards rather than matched by an optional `=?` in
    # the pattern: with `=?` it is the regex engine that decides whether `-l=bug`
    # carries the value `bug` or `=bug`, and POSIX leaves that choice open.
    #
    # A CLUSTER counts as attached too. pflag bundles shorthands, so `-wl bug`
    # and `-wlbug` are `--web --label bug`, and `-wb TEXT` is `--web --body
    # TEXT`. The pattern used to require the judged letter to sit immediately
    # after the dash, so every one of those went to passthrough whole: two
    # category labels filed behind `-wl`, and behind `-wb` a body that was
    # neither checked nor turned into a file -- both of the things this script
    # exists to do, skipped by one extra character.
    #
    # Only a run of gh's VALUE-LESS shorthands may precede the judged letter,
    # and they are named rather than guessed: -e/--editor and -w/--web are the
    # only ones `gh issue create` and `gh issue edit` have. That matters,
    # because splitting on the judged letter alone would read `-abug` -- an
    # assignee called `bug` -- as `-a -b ug`, inventing a body out of somebody
    # else's value. Anything this cannot split correctly is left exactly as it
    # was typed: gh knows its own flags, and a cluster gh does not know is one
    # gh rejects, so nothing is filed either way.
    if [[ "$1" =~ ^-([ew]*)([tbFl])(.*)$ ]]; then
      local sh_bools="${BASH_REMATCH[1]}" sh_flag="-${BASH_REMATCH[2]}"
      local sh_value="${BASH_REMATCH[3]}" sh_i
      local -a sh_head=()
      for ((sh_i = 0; sh_i < ${#sh_bools}; sh_i++)); do
        sh_head+=("-${sh_bools:sh_i:1}")
      done
      if [[ -n "$sh_value" ]]; then
        set -- "${sh_head[@]}" "$sh_flag" "${sh_value#=}" "${@:2}"
      else
        set -- "${sh_head[@]}" "$sh_flag" "${@:2}"
      fi
    fi
    case "$1" in
      --title|-t)    (($# >= 2)) || fail_usage "$1 needs a value"
                     title="$2"; title_set=1; shift 2 ;;
      --title=*)     title="${1#--title=}"; title_set=1; shift ;;
      # -b is gh's documented shorthand for --body. Missing here, it fell into
      # passthrough with its text, so `edit 12 -b "..."` skipped the body check
      # entirely AND left the body inline on the gh command line.
      --body|-b)     (($# >= 2)) || fail_usage "$1 needs a value"
                     body_text="$2"; body_text_set=1; shift 2 ;;
      --body=*)      body_text="${1#--body=}"; body_text_set=1; shift ;;
      --body-file|-F) (($# >= 2)) || fail_usage "$1 needs a value"
                     body_file="$2"; shift 2 ;;
      --body-file=*) body_file="${1#--body-file=}"; shift ;;
      --label|-l|--add-label|--remove-label|--label=*|--add-label=*|--remove-label=*)
                     local flag value
                     case "$1" in
                       *=*) flag="${1%%=*}"; value="${1#*=}"; shift ;;
                       *)   (($# >= 2)) || fail_usage "$1 needs a value"
                            flag="$1"; value="$2"; shift 2 ;;
                     esac
                     [[ "$flag" == -l ]] && flag=--label
                     # gh's label flags are string slices: `--label a,b` is two
                     # labels. Split them so each one is judged, and emit them
                     # one per flag so the printed command is unambiguous.
                     #
                     # AND TRIM. `--label "bug, enhancement"` -- a comma-separated
                     # list written with the space a person puts after a comma --
                     # split into `bug` and ` enhancement`, and the leading space
                     # made the second one a name in neither CATEGORY_LABELS nor
                     # STATE_LABELS. So both label rules went blind: two
                     # categories were accepted and filed, two states were
                     # accepted and filed, and `--label "needs-triage, bug"` was
                     # refused for having no category when it plainly had one.
                     # gh accepts the spaced form itself, so this is ordinary
                     # usage rather than an evasion.
                     #
                     # The trimmed name is also what reaches gh. A label called
                     # " enhancement" does not exist in any repo, so forwarding
                     # the untrimmed word would trade a rule this script failed
                     # to apply for an error from gh; and this is the same
                     # normalisation already done for `-l=bug`, not a rewrite of
                     # anything the author meant.
                     local part; local -a parts=()
                     IFS=',' read -r -a parts <<<"$value"
                     for part in "${parts[@]}"; do
                       part="${part#"${part%%[![:space:]]*}"}"
                       part="${part%"${part##*[![:space:]]}"}"
                       [[ -n "$part" ]] || continue
                       case "$flag" in
                         --label|--add-label) add_labels+=("$part") ;;
                       esac
                       label_argv+=("$flag" "$part")
                     done
                     ;;
      --dry-run)     dry=1; shift ;;
      -h|--help)     usage; exit 0 ;;
      # Everything else is gh's business, not this script's: --repo, --assignee,
      # --milestone, --project. They keep their order relative to each other,
      # but NOT relative to the flags this script rewrites: the command is
      # rebuilt below as title, body-file, labels, then these.
      #
      # `--` GETS NO SPECIAL TREATMENT HERE. It is collected like any other
      # unrecognised word, and the arguments after it are still read by the
      # cases above -- `-- --add-label bug` sets a label rather than handing gh
      # two literal words -- and it is re-emitted after the rewritten flags, so
      # it does not even keep the arguments it was written in front of. That is
      # survivable because `gh issue create` and `gh issue edit` take no
      # positional argument other than the issue number, so there is nothing a
      # `--` would be protecting. It is written down because the previous
      # comment claimed the opposite, and a caller who believed it would have
      # been handed a silently different command.
      *)             passthrough+=("$1"); shift ;;
    esac
  done

  # The flag names differ per subcommand, and gh rejects the wrong one with a
  # message about a flag rather than about the convention.
  local l
  for l in "${label_argv[@]}"; do
    case "$sub:$l" in
      create:--add-label|create:--remove-label)
        fail_usage 'create takes --label; --add-label and --remove-label are edit flags' ;;
      edit:--label)
        fail_usage 'edit takes --add-label / --remove-label, not --label' ;;
    esac
  done

  if ((title_set)); then
    check_title "$title"
  elif [[ "$sub" == create ]]; then
    fail_usage 'create needs --title'
  fi

  if ((body_text_set)) && [[ -n "$body_file" ]]; then
    fail_usage 'pass either --body or --body-file, not both'
  fi
  if [[ "$sub" == create ]] && ((body_text_set == 0)) && [[ -z "$body_file" ]]; then
    fail_usage 'create needs a body: --body-file PATH, or --body TEXT'
  fi

  # An inline body is written out and passed as a file. gh is never handed body
  # text on the command line: a body is long, carries newlines and backticks,
  # and every one of those is a way for a body to be mangled or to be mistaken
  # for something else on its way through a shell.
  if ((body_text_set)); then
    TMP_BODY="$(mktemp "${TMPDIR:-/tmp}/gh-issue-body.XXXXXX")" \
      || fail_usage 'could not create a temporary file for --body'
    printf '%s\n' "$body_text" >"$TMP_BODY"
    body_file="$TMP_BODY"
  fi

  [[ -n "$body_file" ]] && check_body "$body_file"
  # A new issue has to arrive carrying its category; an edit only has to not
  # break the rule, because the issue already carries whatever it was given.
  local require_category=0
  [[ "$sub" == create ]] && require_category=1
  check_labels "$require_category" "${add_labels[@]}"

  local -a argv=(gh issue "$sub")
  [[ "$sub" == edit ]] && argv+=("$number")
  ((title_set)) && argv+=(--title "$title")
  [[ -n "$body_file" ]] && argv+=(--body-file "$body_file")
  argv+=("${label_argv[@]}")
  argv+=("${passthrough[@]}")

  if [[ "$dry" != 0 ]]; then
    local out="" a
    for a in "${argv[@]}"; do out+="$(shell_quote "$a") "; done
    printf '%s\n' "${out% }"
    if [[ -n "$TMP_BODY" ]]; then
      warn 'note: --body went to a temporary file, which this run removes again' \
        'pass --body-file to keep the file the printed command names.'
    fi
    exit 0
  fi

  command -v gh >/dev/null 2>&1 || fail_usage 'gh is not installed'
  "${argv[@]}"
  exit $?
}

main "$@"
