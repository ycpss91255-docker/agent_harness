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
#   .claude/commands/<name> per command, same reason as skills
#   .claude/skills          -> ../.agents/skills   (Claude Code does not read
#   .claude/hooks           -> ../.agents/hooks     .agents/ itself)
#   CLAUDE.md               -> AGENTS.md
#
# What is COPIED ONCE, then left alone (the consumer owns it):
#   AGENTS.md               project instructions
#   .agents/hooks.json      which hooks agy fires -- policy, not content
#   .claude/settings.json   the same for Claude Code
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

echo "skills"
fan_out .agents/skills 2 dist/agents/skills
echo "hooks"
fan_out .agents/hooks 2 dist/agents/hooks
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
[[ -L CLAUDE.md && "$(readlink CLAUDE.md)" == "AGENTS.md" ]] \
  && say "ok       CLAUDE.md" \
  || { act "link     CLAUDE.md -> AGENTS.md"
       ((DRY)) || { rm -f CLAUDE.md; ln -s AGENTS.md CLAUDE.md; }; }

printf '\n%s\n' "$( ((DRY)) && echo 'dry run: nothing changed' || echo 'done' )"
