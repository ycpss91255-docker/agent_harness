#!/usr/bin/env bash
# ci.sh -- checks that run on every push and pull request.
#
# These guard the invariants this repo actually depends on. Each one maps to a
# failure we hit while building it:
#   structure  a broken or missing symlink silently stops Claude Code from
#              seeing the shared skills
#   json       .agents/hooks.json in the wrong shape is only reported in agy's
#              log, never in its output
#   frontmatter a SKILL.md without name/description is not registered by any
#              agent, and nothing says so
#   lock       a skill directory that is not in skills-lock.json cannot be
#              restored after a clone
#
# verify-agents.sh is deliberately not run here: it needs the three CLI agents
# and API credentials, so it stays a local check.
#
# Usage: script/ci/ci.sh [lint|json|frontmatter|structure|lock|all]
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

# Tools are pinned by DIGEST, not by tag: a tag can be re-pushed to different
# content, so a tag pin says which label was requested, not which bytes ran.
# Neither is visible to dependabot -- it reads `uses:` refs and manifest files,
# not image references inside a shell script -- so these are updated by hand.
# tool-pin: shellcheck dockerhub koalaman/shellcheck v0.10.0
SHELLCHECK_IMAGE="koalaman/shellcheck@sha256:2097951f02e735b613f4a34de20c40f937a6c8f18ecb170612c88c34517221fb"
# tool-pin: actionlint dockerhub rhysd/actionlint 1.7.12
ACTIONLINT_IMAGE="rhysd/actionlint@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667"

# Run a pinned image over the repo. Refuses to fall back to a host binary: an
# unpinned local tool is the drift this is here to prevent.
run_pinned() {
  local img="$1"; shift
  if ! command -v docker >/dev/null; then
    printf '  FAIL docker is required to run %s\n' "${img%%@*}"
    return 1
  fi
  docker run --rm -v "$PWD":/repo -w /repo "$img" "$@"
}

fail=0
ok()   { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }
head_() { printf '\n### %s\n' "$*"; }

check_lint() {
  head_ shellcheck
  # Pinned by digest, not by the runner's package: Ubuntu 22.04 and 24.04 ship
  # different shellcheck versions, and a version bump adds and removes checks.
  # Without this, the same commit can go red purely because the OS moved.
  # -S warning: the check_* functions are called indirectly as "check_${c}",
  # which shellcheck reports as unreachable (SC2317, info).
  local f
  while IFS= read -r f; do
    if run_pinned "$SHELLCHECK_IMAGE" -x -S warning "$f"; then ok "$f"; else bad "$f"; fi
    # Ours only. dist/agents/skills/ is vendored third-party code: linting it
    # would let an upstream commit turn this repo red, and the fix would be to
    # diverge from the content hash in skills-lock.json.
  done < <(find script dist/script .agents/hooks -name '*.sh' -type f | LC_ALL=C sort)
}

check_actionlint() {
  head_ actionlint
  # A typo in a workflow is close to invisible: a bad `runs-on` label queues
  # the job forever rather than failing it.
  if run_pinned "$ACTIONLINT_IMAGE" -color; then ok "workflows"; else bad "workflows"; fi
}

check_json() {
  head_ "json syntax"
  local f
  for f in .agents/hooks.json .claude/settings.json skills-lock.json; do
    [ -e "$f" ] || { bad "$f missing"; continue; }
    if python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$f"; then
      ok "$f"
    else
      bad "$f"
    fi
  done
}

check_frontmatter() {
  head_ "SKILL.md frontmatter"
  local f name desc
  while IFS= read -r f; do
    name=$(awk '/^name:/{print;exit}' "$f")
    desc=$(awk '/^description:/{print;exit}' "$f")
    if [ -z "$name" ] || [ -z "$desc" ]; then
      bad "$f is missing name: or description:"
    else
      ok "$f"
    fi
  done < <(find .agents/skills -name SKILL.md -type f | sort)
}

check_structure() {
  head_ "symlink structure"
  # Claude Code does not read .agents/; these links are what make the shared
  # directory reachable. See README.md.
  local link target
  for pair in \
    ".claude/skills:../.agents/skills" \
    ".claude/hooks:../.agents/hooks" \
    "CLAUDE.md:AGENTS.md"
  do
    link=${pair%%:*}; target=${pair#*:}
    if [ ! -L "$link" ]; then
      bad "$link is not a symlink"
    elif [ "$(readlink "$link")" != "$target" ]; then
      bad "$link -> $(readlink "$link") (expected $target)"
    elif [ ! -e "$link" ]; then
      bad "$link is a dangling symlink"
    else
      ok "$link -> $target"
    fi
  done
  # .claude/commands and .claude/memory must NOT be links into .agents/:
  # only Claude Code can use them.
  if [ -L .claude/commands ]; then
    bad ".claude/commands should be a real directory, not a symlink"
  else
    ok ".claude/commands is a real directory"
  fi
}

check_wiring() {
  head_ "init.sh is idempotent"
  # The root links are what the three agents actually read. If init.sh would
  # still change something, the tree does not match what a consumer gets from
  # a fresh install -- and nothing else would report that.
  local out
  out="$(./init.sh --dry-run 2>&1)" || { bad "init.sh --dry-run failed"; return; }
  local pending
  pending=$(printf '%s' "$out" | grep -cE '^  would ' || true)
  if [ "$pending" = 0 ]; then
    ok "no pending changes"
  else
    bad "$pending pending change(s):"
    printf '%s\n' "$out" | grep -E '^  would ' | sed 's/^/       /'
  fi
}

check_lock() {
  head_ "skills-lock.json covers .agents/skills"
  local locked installed missing extra
  locked=$(python3 -c "import json;print('\n'.join(sorted(json.load(open('skills-lock.json'))['skills'])))")
  # python's sorted() is codepoint order; the shell must use the same collation
  # or comm reports spurious differences (e.g. code-review vs codebase-design).
  installed=$(find dist/agents/skills -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | grep -v '^probe-marker$' | LC_ALL=C sort)
  # comm compares with the current locale too, not just the input order.
  missing=$(LC_ALL=C comm -13 <(printf '%s\n' "$locked") <(printf '%s\n' "$installed"))
  extra=$(LC_ALL=C comm -23 <(printf '%s\n' "$locked") <(printf '%s\n' "$installed"))
  [ -n "$missing" ] && bad "installed but not in skills-lock.json: $(echo "$missing" | tr '\n' ' ')"
  [ -n "$extra" ]   && bad "in skills-lock.json but not installed: $(echo "$extra" | tr '\n' ' ')"
  [ -z "$missing" ] && [ -z "$extra" ] && ok "$(printf '%s\n' "$locked" | wc -l) skills match"
}

# The single list of checks. "all" derives from it, and CI runs only "all",
# so adding a check here gates pull requests immediately -- there is no second
# place to keep in sync.
CHECKS=(lint actionlint json frontmatter structure wiring lock)

target="${1:-all}"
if [ "$target" = all ]; then
  for c in "${CHECKS[@]}"; do "check_${c}"; done
elif printf '%s\n' "${CHECKS[@]}" | grep -qx "$target"; then
  "check_${target}"
else
  printf 'unknown target: %s\navailable: %s all\n' "$target" "${CHECKS[*]}" >&2
  exit 2
fi

printf '\n'
[ "$fail" = 0 ] && echo "all checks passed" || echo "one or more checks failed"
exit "$fail"
