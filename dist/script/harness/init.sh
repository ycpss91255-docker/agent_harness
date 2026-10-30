#!/usr/bin/env bash
# init.sh - wire the agent harness into a repository root.
#
# The three agents locate their configuration by walking UP from the working
# directory to the repository root, so `.agents/`, `.claude/`, `AGENTS.md` and
# `CLAUDE.md` have to exist AT THE ROOT. A subtree lands in a subdirectory, so
# something has to bridge the two. This is that something.
#
# Bootstrap in a consumer repo:
#   git subtree add --prefix=.agent_harness \
#       https://github.com/ycpss91255-docker/agent_harness.git main --squash
#   ./.agent_harness/init.sh
#
# Re-running is safe and is how drift is repaired: every link is recreated,
# and links into the harness for skills it no longer ships are removed.
#
# What is LINKED (updates arrive with an upgrade):
#   .agents/skills/<name>   per skill, so the consumer's own skills sit
#                           alongside the vendored ones in the same directory
#   .agents/hooks/<name>    per hook script, same reason
#   .agents/scripts/<name>  per script an agent is told to RUN. Separate from
#                           hooks/ because nothing fires these: a hook is
#                           invoked by the agent, a script is invoked by the
#                           author. Under .agents/ rather than .claude/ because
#                           all three agents call them, and because a script is
#                           the one rule-carrier that no agent's hook-trust
#                           gate can switch off.
#   .claude/commands/<name> per command, same reason as skills
#   .claude/skills          -> ../.agents/skills   (Claude Code does not read
#   .claude/hooks           -> ../.agents/hooks     .agents/ itself)
#   CLAUDE.md               -> AGENTS.md
#
# What is COPIED ONCE, then left alone (the consumer owns it):
#   AGENTS.md               project instructions
#   .agents/hooks.json      which hooks agy fires -- policy, not content
#   .claude/settings.json   the same for Claude Code
#   .codex/hooks.json       the same for Codex. It is NOT under .agents/,
#                           because .codex/ is the directory Codex reads
#                           project hooks from and .agents/ is measurably not
#                           read (measured 2026-09-09, codex-cli 0.153.2: the
#                           same file placed at .agents/hooks.json is not
#                           listed by the app-server's hooks/list). hooks.json
#                           is one of two files it reads THERE -- [[hooks.*]]
#                           blocks in .codex/config.toml are project hooks too,
#                           listed by hooks/list with source "project". This
#                           harness ships hooks.json; a consumer keeping theirs
#                           in config.toml is not doing it wrong, and copy_once
#                           will not notice, which is why the gate report below
#                           is a report and not a verdict.
#
# CODEX HOOKS ARE DOUBLY TRUST-GATED, AND BOTH GATES FAIL SILENTLY IN
# `codex exec`. A delivered .codex/hooks.json does nothing until (1) the repo is
# a trusted project in ~/.codex/config.toml -- named by its exact root path,
# because trust does not descend from a parent entry -- and (2) the hook itself
# has been reviewed: a fresh clone's hooks list as trustStatus "untrusted", the
# review happens in the TUI, and the recorded hash changes whenever the hook
# config changes. Measured: with the project untrusted, or with the hook
# unreviewed, `codex exec` printed no hook line and no warning at all; the hook
# simply did not run. (Outside `codex exec` the trust gate is loud -- the
# app-server and the TUI print an ERROR naming the untrusted .codex folder.)
#
# So an install being green is not a promise that Codex will fire the hook on
# that machine -- only that the file a trusted, reviewed Codex would read is in
# place. That gap is exactly the one report_unwired exists to close for
# .claude/settings.json, so it is not left silent either: report_codex_gates
# prints both gates whenever .codex/hooks.json is present after the copy step.
# It cannot clear them -- ~/.codex/config.toml is the consumer's file and the
# review is an interactive flow -- so it says what is left to do and stops.
#
# COPY-ONCE MEETS A REPO THAT ALREADY HAS THE FILE. Adopting the harness into an
# existing project is the normal case, and an existing project usually already
# has .claude/settings.json. copy_once then keeps the consumer's file, which is
# right -- it is theirs -- but every hook this harness ships is wired from one of
# those policy files, so the hooks are delivered and never fire. Nothing said so:
# the install printed "keep .claude/settings.json (yours)" and finished green.
#
# init.sh does not edit a file the consumer owns, so it does not wire the hook
# for them. What it does now is refuse to be silent: a kept policy file that
# does not name a shipped hook is reported as UNWIRED, with the entry to add.
# Merging harness-owned entries into a consumer's config properly -- a managed
# region, an opt-out for a hook they deliberately removed, and upgrade semantics
# for both -- is a change to what copy_once means and is not attempted here.
#
# Options:
#   --dry-run   print what would change, change nothing
#   -h|--help   this text

set -euo pipefail

usage() { sed -n '/^# init\.sh/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; }

DRY=0
while (($#)); do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'init.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
act()  { if ((DRY)); then printf '  would %s\n' "$*"; else printf '  %s\n' "$*"; fi; }

# Locate the subtree root: the directory carrying both markers. Walking up from
# this script means the layout below it can change without breaking discovery.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HARNESS="${SCRIPT_DIR}"
while [[ "${HARNESS}" != "/" ]]; do
  [[ -f "${HARNESS}/.version" && -d "${HARNESS}/dist" ]] && break
  HARNESS="$(cd -- "${HARNESS}/.." && pwd -P)"
done
[[ -f "${HARNESS}/.version" ]] || {
  printf 'init.sh: no .version + dist/ above %s\n' "${SCRIPT_DIR}" >&2; exit 1
}

# Repo root, and the harness path relative to it. Deriving the prefix from the
# directory's own name means a consumer that renames the subtree keeps working
# without editing anything here.
ROOT="$(git -C "${HARNESS}" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "${ROOT}" ]] || { printf 'init.sh: not inside a git repository\n' >&2; exit 1; }
if [[ "${HARNESS}" == "${ROOT}" ]]; then
  PREFIX=""              # the harness repo itself; it consumes its own payload
else
  PREFIX="${HARNESS#"${ROOT}"/}"
fi

printf 'harness  %s\n' "${HARNESS}"
printf 'repo     %s\n' "${ROOT}"
printf 'version  %s\n' "$(cat "${HARNESS}/.version")"
printf 'prefix   %s\n' "${PREFIX:-<repo root>}"
printf '\n'

cd -- "${ROOT}"

# Build a link target: `depth` levels of ../ then the path under the harness.
target() {
  local depth="$1" path="$2" up=""
  local i; for ((i = 0; i < depth; i++)); do up+="../"; done
  printf '%s%s%s' "${up}" "${PREFIX:+${PREFIX}/}" "${path}"
}

link() {                     # link <path-from-root> <depth> <path-in-harness>
  local at="$1" want; want="$(target "$2" "$3")"
  # Refuse to write through a symlinked parent: `rm` and `ln` inside a
  # directory that is itself a link resolve into the harness and delete the
  # payload. This is defence in depth -- fan_out already replaces such a
  # parent with a real directory before calling here.
  local parent; parent="$(dirname -- "${at}")"
  if [[ -L "${parent}" ]]; then
    printf '  REFUSE   %s (parent %s is a symlink)\n' "${at}" "${parent}" >&2
    return 1
  fi
  if [[ -L "${at}" && "$(readlink "${at}")" == "${want}" ]]; then
    say "ok       ${at}"
    return
  fi
  [[ -e "${at}" || -L "${at}" ]] && act "replace  ${at}" || act "link     ${at} -> ${want}"
  ((DRY)) && return
  rm -rf -- "${at}"
  mkdir -p -- "$(dirname -- "${at}")"
  ln -s -- "${want}" "${at}"
}

copy_once() {                # copy_once <path-from-root> <path-in-harness>
  local at="$1" from="${HARNESS}/$2"
  if [[ -e "${at}" ]]; then
    say "keep     ${at} (yours)"
    return
  fi
  act "copy     ${at} <- $2"
  ((DRY)) || { mkdir -p -- "$(dirname -- "${at}")"; cp -- "${from}" "${at}"; }
}

# Per-item links, so the consumer's own entries live in the same directory.
fan_out() {                  # fan_out <dir-from-root> <depth> <dir-in-harness>
  local dir="$1" depth="$2" src="$3" name
  # The container must be a real directory. If an older layout left a symlink
  # here, every write below would land inside the harness instead.
  if [[ -L "${dir}" ]]; then
    act "unlink   ${dir} (must be a real directory)"
    ((DRY)) || rm -f -- "${dir}"
  fi
  ((DRY)) && [[ ! -d "${dir}" ]] && { act "mkdir    ${dir}"; return; }
  mkdir -p -- "${dir}"
  for path in "${HARNESS}/${src}"/*; do
    [[ -e "${path}" ]] || continue
    name="$(basename -- "${path}")"
    link "${dir}/${name}" "${depth}" "${src}/${name}"
  done
  # Drop links into the harness for entries it no longer ships.
  for path in "${dir}"/*; do
    [[ -L "${path}" ]] || continue
    name="$(basename -- "${path}")"
    [[ -e "${HARNESS}/${src}/${name}" ]] && continue
    case "$(readlink "${path}")" in
      *"${src}/${name}") act "prune    ${path} (no longer shipped)"
                         ((DRY)) || rm -f -- "${path}" ;;
    esac
  done
}

# Every hook this harness ships has to be named by a policy file or it never
# runs, and the policy files are copy_once. A grep is the right weight for this:
# it is a warning, not a verdict, it needs no JSON parser in a script that
# otherwise has no dependencies, and the failure it catches is the file not
# mentioning the hook AT ALL. A file that names the hook under the wrong event
# is script/ci/ci.sh check_hook_wiring's business, where there is a parser.
report_unwired() {           # report_unwired <policy-file> <how-line>...
  local at="$1"; shift
  local name missing=0 path
  [[ -e "${at}" ]] || return 0
  for path in "${HARNESS}"/dist/agents/hooks/*.sh; do
    [[ -f "${path}" ]] || continue
    name="$(basename -- "${path}")"
    grep -q -F -e "${name}" -- "${at}" && continue
    printf '  UNWIRED  %s does not name %s, so that hook never fires\n' "${at}" "${name}" >&2
    missing=1
  done
  if ((missing)); then
    local line
    for line in "$@"; do printf '           %s\n' "${line}" >&2; done
    printf '           this file is yours, so init.sh will not edit it.\n' >&2
  fi
  return 0
}

# Delivering .codex/hooks.json is not the same as Codex running it, and the
# difference is invisible from here: both gates live outside this repo (a
# trust entry in the consumer's ~/.codex/config.toml, and an interactive hook
# review), and under `codex exec` failing either produces no hook line and no
# warning. An install that printed "copy .codex/hooks.json" and stopped would
# read as "the Codex hook is live", which is the same silence report_unwired
# was added to end for .claude/settings.json. So it is said out loud, every
# time the file is there, whether it was just copied or kept.
report_codex_gates() {
  # In a dry run the file has not been written yet, so ask the payload instead:
  # a dry run that stayed quiet about the gates would be the more misleading of
  # the two, since it is what a cautious consumer reads first.
  [[ -e .codex/hooks.json ]] \
    || { ((DRY)) && [[ -e "${HARNESS}/dist/codex/hooks.json" ]]; } \
    || return 0
  {
    printf '  GATED    .codex/hooks.json is delivered; Codex will not run it yet\n'
    printf '           1. trust the project -- add to ~/.codex/config.toml:\n'
    printf '                [projects."%s"]\n' "${ROOT}"
    printf '                trust_level = "trusted"\n'
    printf '              the entry must name that exact path; trust does not\n'
    printf '              descend from an entry for a parent directory.\n'
    printf '           2. review the hook -- start `codex` in this repo and accept\n'
    printf '              it. The recorded hash changes whenever the file changes.\n'
    printf '           under `codex exec` both gates fail in SILENCE: no hook line,\n'
    printf '           no warning, nothing runs. Neither is init.sh'"'"'s to clear.\n'
  } >&2
  return 0
}

echo "skills"
fan_out .agents/skills 2 dist/agents/skills
echo "hooks"
fan_out .agents/hooks 2 dist/agents/hooks
echo "scripts"
# The redirect hook is shipped and wired in both config files, so a consumer's
# fresh install carries a hook naming .agents/scripts/gh-issue.sh. Shipping the
# hook without the script it names hands that install an instruction it cannot
# follow, which is exactly what happened while the script lived in script/.
fan_out .agents/scripts 2 dist/agents/scripts
echo "commands"
fan_out .claude/commands 2 dist/claude/commands
echo "claude entry points"
# Claude Code reads .claude/ only; these two are what make the shared
# directories reachable from it.
[[ -L .claude/skills && "$(readlink .claude/skills)" == "../.agents/skills" ]] \
  && say "ok       .claude/skills" \
  || { act "link     .claude/skills -> ../.agents/skills"
       ((DRY)) || { rm -rf .claude/skills; ln -s ../.agents/skills .claude/skills; }; }
[[ -L .claude/hooks && "$(readlink .claude/hooks)" == "../.agents/hooks" ]] \
  && say "ok       .claude/hooks" \
  || { act "link     .claude/hooks -> ../.agents/hooks"
       ((DRY)) || { rm -rf .claude/hooks; ln -s ../.agents/hooks .claude/hooks; }; }
echo "yours to edit"
copy_once AGENTS.md             dist/template/AGENTS.md
copy_once .agents/hooks.json    dist/agents/hooks.json
copy_once .claude/settings.json dist/claude/settings.json
copy_once .codex/hooks.json     dist/codex/hooks.json
report_unwired .claude/settings.json \
  'add it under hooks.PreToolUse with matcher "Bash":' \
  '  {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.agents/hooks/<hook>"}'
report_unwired .agents/hooks.json \
  'add it under <group>.PreToolUse with matcher "*":' \
  '  {"type": "command", "command": "./hooks/<hook>"}'
# Codex runs a hook command through a shell, from the SESSION's directory rather
# than the repo root (measured: a session started in sub/deeper ran the hook with
# that as its cwd), and sets no project-directory variable of its own. So the
# path has to locate the root itself, and `git rev-parse` is the one way that
# works from any depth -- Codex requires a git repo anyway.
report_unwired .codex/hooks.json \
  'add it under hooks.PreToolUse with matcher "*":' \
  '  {"type": "command",' \
  '   "command": "\"$(git rev-parse --show-toplevel)/.agents/hooks/<hook>\""}'
report_codex_gates
[[ -L CLAUDE.md && "$(readlink CLAUDE.md)" == "AGENTS.md" ]] \
  && say "ok       CLAUDE.md" \
  || { act "link     CLAUDE.md -> AGENTS.md"
       ((DRY)) || { rm -f CLAUDE.md; ln -s AGENTS.md CLAUDE.md; }; }

printf '\n%s\n' "$( ((DRY)) && echo 'dry run: nothing changed' || echo 'done' )"
