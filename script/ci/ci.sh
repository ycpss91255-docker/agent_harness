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
#   gh_issue   the issue conventions are only real if something applies them;
#              script/gh-issue.sh is where they live, and a stub gh installed
#              first on PATH is what lets CI assert on the exact command it
#              would run while making it impossible for it to reach github.com.
#              Three layers now: the stub, a counted tripwire behind it, and an
#              invalid credential in every case's environment
#   redirect_hook a PreToolUse hook signals its verdict on stdout and exits 0
#              either way, so a hook that silently stopped firing looks exactly
#              like a hook that approves of everything
#   hook_wiring a hook that no config file names never runs, and running the
#              script by path -- which redirect_hook does -- passes either way.
#              Three configs now, one per agent: Codex acquired project hooks
#              (.codex/hooks.json), and its path rule differs from the other
#              two, so a command that is correct for Claude Code or agy is
#              wired and inert there
#   ship       a hook that ships and a script that does not is an install
#              telling its author to run a file it never delivered -- and the
#              same is true of a message citing a document dist/ does not ship,
#              or a hook delivered into a repo whose config never names it
#
# verify-agents.sh is deliberately not run here: it needs the three CLI agents
# and API credentials, so it stays a local check.
#
# Usage: script/ci/ci.sh [lint|json|frontmatter|structure|lock|gh_issue|
#                         redirect_hook|hook_wiring|ship|all]
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
    #
    # dist/agents/hooks is listed alongside .agents/hooks because a shipped hook
    # is a real file under dist/ and only a symlink under .agents/, and `-type f`
    # does not match a symlink. Without this entry the hooks that reach consumers
    # are precisely the ones that never get linted.
    #
    # dist/agents/scripts is here for the same reason: gh-issue.sh is a real
    # file only under dist/, and script/gh-issue.sh is now a symlink to it, so
    # `-type f` sees it at the dist path and nowhere else.
  done < <(find script dist/script .agents/hooks dist/agents/hooks \
    dist/agents/scripts -name '*.sh' -type f | LC_ALL=C sort)
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
  # The dist/ copies are what init.sh hands a consumer on a fresh install. A
  # syntax error in one of those is not visible in this repo at all -- it breaks
  # somebody else's clone.
  for f in .agents/hooks.json .claude/settings.json .codex/hooks.json \
           skills-lock.json \
           dist/agents/hooks.json dist/claude/settings.json dist/codex/hooks.json; do
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

# A PreToolUse payload for <command>, built the way Claude Code builds it.
hook_payload() {
  python3 -c 'import json,sys
print(json.dumps({"session_id": "ci", "hook_event_name": "PreToolUse",
                  "tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1"
}

# Reduce a hook's stdout to one word. Three of them are deliberately distinct
# even though Claude Code runs the command in all three cases:
#   allow        the hook said nothing -- the command goes to the normal
#                permission flow, which is the only correct silent outcome
#   force-allow  the hook emitted permissionDecision "allow", which WAIVES the
#                permission prompt for that command. This hook must never do
#                that; collapsing it into "allow" would let a regression that
#                auto-approves every Bash command pass the whole table.
#   malformed    Claude Code prints unparseable hook output and runs the
#                command anyway, so a broken emitter would otherwise read as a
#                deliberate approval.
hook_verdict() {
  python3 -c 'import json,sys
raw = sys.stdin.read().strip()
if not raw:
    print("allow"); raise SystemExit
try:
    out = json.loads(raw)
except Exception:
    print("malformed"); raise SystemExit
decision = (out.get("hookSpecificOutput") or {}).get("permissionDecision")
if decision == "allow":
    print("force-allow")
elif decision:
    print(decision)
elif out.get("systemMessage"):
    print("note")
else:
    # JSON with neither a decision nor a message is not a usable hook reply.
    print("malformed")'
}

# --- the gh sandbox ---------------------------------------------------------
#
# A test suite is kept off the network by its ENVIRONMENT, never by a flag the
# code under test is trusted to honour. This suite learned that the expensive
# way: the guard used to be GH_ISSUE_DRY_RUN, a variable read by
# script/gh-issue.sh itself, so the safety mechanism lived inside the code under
# test. The script had a defect on that path, the guard did nothing, and the
# suite filed three real issues against this repo.
#
# So the check builds its own `gh` in a temporary directory and puts it first on
# PATH for every invocation it makes. The stub records the argv it was handed,
# prints it and exits 0. It never execs the real gh, opens no socket and needs
# no credentials. No defect in script/gh-issue.sh -- and no future edit to it --
# can reach github.com from in here, because within this check there is no real
# gh to reach it with. The script's own --dry-run stays as a convenience for a
# human reading a command before running it; nothing here depends on it.
#
# The stub is also the better assertion. It records the argv gh was actually
# handed, so an accept case checks the command that would really have run rather
# than a line the script printed about itself. The cases therefore run the
# script FOR REAL, into the stub, and gi_dry additionally holds --dry-run to its
# promise: same command, and gh not called at all.
#
# The verdict of a refusal is its exit status AND its text: a refusal that does
# not name the rule it applied is one the author cannot act on, and "it exited
# non-zero" is passed by a script that is simply broken. A refusal must also
# leave the stub untouched -- that is what says the refusal happened before gh,
# not after it.
#
# THREE LAYERS, NOT ONE. The stub is the first and the one that does the work;
# the other two exist because a single layer is a single point of failure, and
# this suite has already been on the wrong side of that once.
#
#   1  the stub, first on PATH. Answers to the name `gh`, records argv, execs
#      nothing. Every case resolves here.
#
#   2  a tripwire, second on PATH, ahead of the real gh. It is what a call that
#      is NOT answered by the stub reaches -- a mangled PATH, a torn-down
#      sandbox, a stub that failed to install -- and it records the call and
#      exits non-zero instead of passing it on. The real binary sits behind it
#      and is never the next thing on the list. This is also how the suite says
#      "the real gh was never executed" as a MEASUREMENT rather than an
#      inference from PATH order: the tripwire's log is the count of calls that
#      got past the stub, and gi_no_real_gh asserts that count is zero. The
#      tripwire is proved to fire before any case runs, so a zero means
#      something.
#
#   3  an obviously invalid credential, in every environment a case runs in.
#      GH_TOKEN and the three other names gh reads are set to a value that is
#      plainly a test string, and GH_CONFIG_DIR points into the sandbox so
#      there is no stored login either. A call that somehow escaped both layers
#      above would be answered by the API with 401 rather than by mutating an
#      issue. It is exported inside the subshell that starts the script and
#      nowhere else, so it does not leak into the rest of ci.sh or into the
#      shell that ran it.
#
# The real gh is NOT removed from PATH: on this machine it is /usr/bin/gh, and
# dropping /usr/bin would take python3, jq and mktemp with it -- the tools the
# script under test needs. Shadowing it with a stub and backing that with a
# counted tripwire is the arrangement that is both safe and runnable.
GI_SANDBOX=""; GI_BIN=""; GI_BARE=""; GI_TRAP=""; GI_LOG=""; GI_REAL_LOG=""
GI_ENV_LOG=""
GI_OUT=""; GI_ERR=""; GI_STATUS=0; GI_STDOUT=""; GI_STDERR=""; GI_CALLS=""
# The two PATHs a case may run with, written down once so that every layer is
# in both of them and no invocation can assemble its own by hand:
#   GI_CASE_PATH  stub, tripwire, then the world
#   GI_BARE_PATH  the rule-3 fallback case, which needs a PATH with neither
#                 python3 nor jq on it. Narrower, so it moves further from a
#                 real gh, never towards one -- and the tripwire is still on it.
GI_CASE_PATH=""; GI_BARE_PATH=""

# Layer 3. Plainly a test value and not a credential shape anyone could mistake
# for one: it names this file, says what it is for, and could not authenticate
# against anything.
readonly GI_FAKE_TOKEN='not-a-token-ci-sh-stub-only-0000000000000000000000'

# The DELIVERED path, not the source file and not this repo's own alias. This is
# the path init.sh creates in every install and the path the shipped hook names,
# so it is the one an agent actually runs; driving it means a broken link into
# dist/ fails here rather than in somebody else's clone.
GI_SCRIPT=.agents/scripts/gh-issue.sh

# Cleanup has to survive the check failing part-way: an early return, a bad()
# that abandons the rest, an unbound-variable exit. An EXIT trap is the only
# place that holds for all three, so the sandbox is removed there and not at the
# bottom of the check. check_ship's throwaway install rides the same trap;
# ship_cleanup is defined further down, which is fine because a trap body is
# read when it fires, not when it is set.
#
# EVERY path is cleared, not just GI_SANDBOX. Clearing the root alone left
# GI_BIN and GI_BARE pointing into a directory that had just been deleted, and
# a `PATH="$GI_BIN:$PATH"` built from a stale GI_BIN skips a directory that no
# longer exists and resolves `gh` to /usr/bin/gh -- the real one. That is the
# precise shape of the failure that filed three issues against this repo, left
# armed for whatever ran next.
gi_sandbox_cleanup() {
  [ -n "$GI_SANDBOX" ] && rm -rf -- "$GI_SANDBOX"
  GI_SANDBOX=""; GI_BIN=""; GI_BARE=""; GI_TRAP=""; GI_LOG=""; GI_REAL_LOG=""
  GI_ENV_LOG=""; GI_STDOUT=""; GI_STDERR=""; GI_CASE_PATH=""; GI_BARE_PATH=""
  return 0
}

# Is there a sandbox to run in RIGHT NOW? Asked before every invocation rather
# than assumed from the fact that one was built earlier in the function.
gi_sandbox_is_live() {
  [ -n "$GI_SANDBOX" ] && [ -d "$GI_SANDBOX" ] \
    && [ -x "$GI_BIN/gh" ] && [ -x "$GI_TRAP/gh" ] \
    && [ -n "$GI_LOG" ] && [ -n "$GI_CASE_PATH" ]
}
trap 'gi_sandbox_cleanup; ship_cleanup' EXIT

gi_sandbox_start() {
  GI_SANDBOX="$(mktemp -d)" || return 1
  GI_BIN="$GI_SANDBOX/bin"
  GI_BARE="$GI_SANDBOX/bare"
  GI_TRAP="$GI_SANDBOX/trap"
  GI_LOG="$GI_SANDBOX/gh-calls"
  GI_ENV_LOG="$GI_SANDBOX/gh-credentials"
  GI_REAL_LOG="$GI_SANDBOX/past-the-stub"
  GI_STDOUT="$GI_SANDBOX/out"
  GI_STDERR="$GI_SANDBOX/err"
  mkdir -p "$GI_BIN" "$GI_TRAP" "$GI_SANDBOX/gh-config" || return 1
  : >"$GI_LOG" || return 1
  : >"$GI_ENV_LOG" || return 1
  : >"$GI_REAL_LOG" || return 1
  # Quoted heredoc: the stub is written out verbatim, not expanded here. It
  # quotes each argument the way a person would have to type it, so a captured
  # call can be compared against -- and pasted from -- an ordinary command line.
  cat >"$GI_BIN/gh" <<'STUB'
#!/usr/bin/env bash
# NOT gh. A stand-in installed first on PATH by script/ci/ci.sh check_gh_issue.
# It appends the argv it was handed to $GH_STUB_LOG, prints the same line, and
# exits 0. It never execs, calls or otherwise reaches the real gh.
set -u
quote() {
  if [ -n "$1" ] && [[ "$1" =~ ^[A-Za-z0-9_@%+=:,./-]+$ ]]; then
    printf '%s' "$1"
  else
    printf "'%s'" "${1//\'/\'\\\'\'}"
  fi
}
line="gh"
for arg in "$@"; do line="$line $(quote "$arg")"; done
printf '%s\n' "$line" >>"${GH_STUB_LOG:?the gh stub was run without GH_STUB_LOG}"
# What the real gh would have authenticated with, recorded separately so it
# cannot disturb the argv assertions. This is how the suite checks that the
# invalid credential reached the script's own child rather than only the
# function that exports it.
printf '%s\n' "${GH_TOKEN-<unset>}" >>"${GH_STUB_ENV_LOG:-/dev/null}"
printf '%s\n' "$line"
exit 0
STUB
  chmod +x "$GI_BIN/gh" || return 1

  # Layer 2. Sits between the stub and the real binary on every PATH a case
  # runs with, so a `gh` the stub did not answer is answered HERE and stops. It
  # is the thing that turns "the real gh was never executed" into a number.
  cat >"$GI_TRAP/gh" <<'TRIPWIRE'
#!/usr/bin/env bash
# NOT gh, and not the stub either. A tripwire installed by script/ci/ci.sh
# check_gh_issue immediately AFTER the stub and BEFORE the real gh. Nothing is
# supposed to reach it: every case resolves to the stub. It records the call so
# the suite can assert the count is zero, refuses, and execs nothing.
set -u
quote() {
  if [ -n "$1" ] && [[ "$1" =~ ^[A-Za-z0-9_@%+=:,./-]+$ ]]; then
    printf '%s' "$1"
  else
    printf "'%s'" "${1//\'/\'\\\'\'}"
  fi
}
line="gh"
for arg in "$@"; do line="$line $(quote "$arg")"; done
printf '%s\n' "$line" >>"${GH_TRIPWIRE_LOG:?the gh tripwire was run without GH_TRIPWIRE_LOG}"
printf 'ci.sh: a gh call got past the stub and was stopped here\n' >&2
exit 97
TRIPWIRE
  chmod +x "$GI_TRAP/gh" || return 1

  # A second bin holding the stub and a bash, and NOTHING else. The rule-3
  # length fallback only runs when neither python3 nor jq is on PATH, so
  # exercising it needs a PATH with neither -- which cannot simply be a
  # directory of the real ones, since python3 and bash live side by side. Note
  # the direction: this PATH is narrower than the sandbox's, so it moves further
  # away from a real gh, never towards one. bash is here because the stub's own
  # `#!/usr/bin/env bash` has to resolve.
  mkdir -p "$GI_BARE" || return 1
  ln -s -- "$GI_BIN/gh" "$GI_BARE/gh" || return 1
  ln -s -- "$BASH" "$GI_BARE/bash" || return 1

  GI_CASE_PATH="$GI_BIN:$GI_TRAP:$PATH"
  GI_BARE_PATH="$GI_BARE:$GI_TRAP"
  return 0
}

# The ONE place that decides what a run of the script under test can see. Every
# subshell in this file that starts the script calls it, so there is a single
# statement of the environment rather than four that drift.
#
# Called INSIDE the subshell: everything it exports dies with that subshell, so
# the fake credentials never reach the rest of ci.sh, the other checks, or the
# shell that invoked ci.sh.
gi_env() {                        # gi_env <path>
  export PATH="$1"
  export GH_STUB_LOG="$GI_LOG"
  export GH_STUB_ENV_LOG="$GI_ENV_LOG"
  export GH_TRIPWIRE_LOG="$GI_REAL_LOG"
  # Layer 3: no usable credential, from any of the four names gh reads, and no
  # stored login to fall back on either.
  export GH_TOKEN="$GI_FAKE_TOKEN"
  export GITHUB_TOKEN="$GI_FAKE_TOKEN"
  export GH_ENTERPRISE_TOKEN="$GI_FAKE_TOKEN"
  export GITHUB_ENTERPRISE_TOKEN="$GI_FAKE_TOKEN"
  export GH_CONFIG_DIR="$GI_SANDBOX/gh-config"
  # The suite's guard is the stub, never a flag the code under test honours --
  # and a developer with GH_ISSUE_DRY_RUN exported in their own shell used to
  # watch twenty accept cases fail on an empty stub log, because the real arm
  # inherited it. The environment a case runs in is BUILT here, not borrowed
  # from whoever ran ci.sh.
  unset GH_ISSUE_DRY_RUN
  # The consumer tree check runs the delivered script from inside a throwaway
  # repo; this repo's project dir is not that repo's.
  unset CLAUDE_PROJECT_DIR
}

# Prove the sandbox before a single case runs, and refuse to run them if it does
# not hold. An unproven sandbox is not a sandbox, and running the cases anyway
# is exactly how the three issues got filed.
gi_sandbox_proves() {
  local resolved
  # command -v only resolves; it runs nothing, so this cannot itself reach gh.
  resolved="$(PATH="$GI_CASE_PATH" command -v gh)" || resolved="(not found)"
  if [ "$resolved" != "$GI_BIN/gh" ]; then
    bad "gh does not resolve to the stub (got \"$resolved\"); not running the cases"
    return 1
  fi
  # And the stub records. Called by absolute path, so a PATH mistake here can
  # never fall through to a real gh.
  : >"$GI_LOG"
  GH_STUB_LOG="$GI_LOG" "$GI_BIN/gh" issue list --limit 1 >/dev/null 2>&1
  if [ "$(cat "$GI_LOG")" != "gh issue list --limit 1" ]; then
    bad "the gh stub did not record its arguments; not running the cases"
    return 1
  fi
  : >"$GI_LOG"
  ok "sandbox: gh resolves to $GI_BIN/gh, which records and never execs gh"

  # LAYER 2, PROVED THE SAME WAY. gi_no_real_gh asserts the tripwire's log is
  # empty at the end of the check, and an empty log means nothing unless the
  # tripwire would have written to it. So: take the stub out of the front of the
  # cases' PATH -- the exact accident this layer exists for -- and confirm that
  # what answers to `gh` is the tripwire and not /usr/bin/gh.
  local without="${GI_CASE_PATH#"$GI_BIN":}"
  resolved="$(PATH="$without" command -v gh)" || resolved="(not found)"
  if [ "$resolved" != "$GI_TRAP/gh" ]; then
    bad "with the stub removed, gh resolves to \"$resolved\" and not the tripwire"
    bad "so a call past the stub would reach a real gh; not running the cases"
    return 1
  fi
  : >"$GI_REAL_LOG"
  # Run by absolute path, like the stub above: the resolution was just asserted
  # separately, and a PATH mistake in this line must not be able to fall through
  # to a real gh.
  if GH_TRIPWIRE_LOG="$GI_REAL_LOG" "$GI_TRAP/gh" issue create --title x \
       >/dev/null 2>&1; then
    bad "the tripwire exited 0; it must refuse. Not running the cases"
    return 1
  fi
  if [ "$(cat "$GI_REAL_LOG")" != "gh issue create --title x" ]; then
    bad "the tripwire did not record the call it stopped; not running the cases"
    return 1
  fi
  : >"$GI_REAL_LOG"

  # Where the real binary actually is, so the report says what was shadowed
  # rather than implying there was nothing to shadow.
  local real; real="$(command -v gh 2>/dev/null)" || real=""
  ok "sandbox: past the stub is $GI_TRAP/gh, which records and refuses, ahead of ${real:-no real gh on this machine}"
  return 0
}

# The count, asserted rather than inferred. Every `gh` a case resolved was
# answered by the stub; anything the stub did not answer was answered by the
# tripwire, which is the only other thing on the PATH that responds to the name
# and which records every call it stops. So the number of lines here IS the
# number of calls that got as far as the real binary's position on the list,
# and zero is a measurement of "the real gh was never executed".
#
# AND IT FAILS CLOSED. A missing or unreadable log used to be normalised to
# zero, so the assertion reported "real gh invocations: 0" on no evidence at
# all -- and the states that produce a missing log are exactly the ones it
# exists to catch: a sandbox torn down early, a path cleared, a tripwire that
# never installed. An assertion that cannot read its evidence has not proved
# anything, so it fails.
gi_no_real_gh() {
  local n
  if [ -z "$GI_REAL_LOG" ]; then
    bad "no tripwire log path is set, so nothing proves the real gh was never run"
    return 1
  fi
  if [ ! -f "$GI_REAL_LOG" ] || [ ! -r "$GI_REAL_LOG" ]; then
    bad "the tripwire log is missing or unreadable: $GI_REAL_LOG"
    bad "nothing proves the real gh was never run; treating that as a failure"
    return 1
  fi
  if ! n="$(wc -l <"$GI_REAL_LOG")"; then
    bad "cannot count the tripwire log: $GI_REAL_LOG"
    bad "nothing proves the real gh was never run; treating that as a failure"
    return 1
  fi
  n="$(printf '%s' "$n" | tr -d '[:space:]')"
  if [ -z "$n" ]; then
    bad "the tripwire log produced no count: $GI_REAL_LOG"
    return 1
  fi
  if [ "$n" = 0 ]; then
    ok "real gh invocations: 0 -- nothing got past the stub to the tripwire"
  else
    bad "$n gh call(s) got past the stub; the real binary was the next thing on PATH:"
    sed 's/^/       /' "$GI_REAL_LOG"
    return 1
  fi
  return 0
}

# The one place that decides what environment the script under test sees. The
# subshell exports PATH before the script is even started, so the stub is in
# place for the script and for anything the script itself starts.
gi_invoke() {                     # gi_invoke <dry|real> <args...>
  local mode="$1"; shift
  # A sandbox that is not live is not a sandbox, and running the case anyway is
  # how the real gh gets reached. Asked here, immediately before the run, rather
  # than once at the top of the check.
  if ! gi_sandbox_is_live; then
    bad "the gh sandbox is not live; refusing to run: $*"
    GI_STATUS=125; GI_OUT=""; GI_ERR=""; GI_CALLS=""
    return 1
  fi
  : >"$GI_LOG"
  (
    gi_env "$GI_CASE_PATH"
    [ "$mode" = dry ] && export GH_ISSUE_DRY_RUN=1
    exec "$GI_SCRIPT" "$@"
  ) >"$GI_STDOUT" 2>"$GI_STDERR"
  GI_STATUS=$?
  GI_OUT="$(cat "$GI_STDOUT")"
  GI_ERR="$(cat "$GI_STDERR")"
  GI_CALLS="$(cat "$GI_LOG")"
}

gi()     { gi_invoke real "$@"; } # gi <args...>      for real, into the stub
gi_dry() { gi_invoke dry  "$@"; } # gi_dry <args...>  the script's own dry run

gi_refuses() {                    # gi_refuses <substring of the refusal> <args...>
  local want="$1"; shift
  # Run for real. A refusal that only holds in dry-run is not a refusal, and
  # this is the arm where reaching gh would have cost something.
  gi "$@"
  if [ -n "$GI_CALLS" ]; then
    bad "a refused command still called gh: $GI_CALLS"
  elif [ "$GI_STATUS" = 0 ]; then
    bad "expected a refusal, got exit 0 and \"$GI_OUT\": $*"
  elif [ -n "$GI_OUT" ]; then
    # A refused command must not also print a gh command line: printing one is
    # how a refusal gets copied and run by hand anyway.
    bad "refused but still printed a gh command: $GI_OUT"
  elif [[ "$GI_ERR" != *"$want"* ]]; then
    bad "refusal does not mention \"$want\": $(printf '%s' "$GI_ERR" | head -2 | tr '\n' ' ')"
  else
    ok "refused ($want)  $*"
  fi
}

gi_accepts() {                    # gi_accepts <expected gh command> <args...>
  local want="$1"; shift
  # The assertion that matters: the argv the stub was actually handed.
  gi "$@"
  if [ "$GI_STATUS" != 0 ]; then
    bad "expected success, got exit $GI_STATUS: $(printf '%s' "$GI_ERR" | head -2 | tr '\n' ' ')"
  elif [ "$GI_CALLS" != "$want" ]; then
    bad "gh was called as: $GI_CALLS"
    bad "expected:         $want"
  else
    ok "$GI_CALLS"
  fi
  # And --dry-run keeps its promise: it prints that same command and calls gh
  # not at all. This is a convenience feature being checked, not a safety one --
  # the safety is the stub, and it is in place for this run too.
  gi_dry "$@"
  if [ -n "$GI_CALLS" ]; then
    bad "--dry-run called gh: $GI_CALLS"
  elif [ "$GI_STATUS" != 0 ]; then
    bad "--dry-run: expected success, got exit $GI_STATUS: $(printf '%s' "$GI_ERR" | head -2 | tr '\n' ' ')"
  elif [ "$GI_OUT" != "$want" ]; then
    bad "--dry-run printed:  $GI_OUT"
    bad "--dry-run expected: $want"
  else
    ok "--dry-run prints the same command and calls nothing"
  fi
}

check_gh_issue() {
  head_ "gh-issue.sh, the issue entry point"
  # The title rules used to live in a PreToolUse hook that was handed the whole
  # Bash command string and had to find the title inside it. Testing that meant
  # simulating hook payloads full of quoting forms, and the thing under test was
  # a hand-written shell parser: 22 then 17 review defects, ending on a FALSE
  # DENY of this repo's own documented recipe. The rules live in a script now,
  # so the shell parses the arguments and the title arrives as argv -- which is
  # also why these cases are ordinary command lines rather than payloads.
  #
  # Every case runs inside the gh sandbox above: a stub gh, first on PATH, that
  # records its argv and exits 0. CI must never file a real issue -- a suite that
  # created issues to test the rules would be switched off within a week, and
  # the rules would go untested -- and the thing that guarantees that is the
  # environment the cases run in, not a flag the script is asked to honour. The
  # stub is also what makes it possible to assert on the exact gh command, which
  # is where "always --body-file" and the label handling are actually visible.
  local script="$GI_SCRIPT"
  if [ ! -x "$script" ]; then
    bad "$script is missing or not executable"
    return
  fi
  # This repo's own documented invocation path is a symlink to the same file.
  # It is what everything here used to call and what its own docs still show, so
  # it has to keep resolving to exactly the file the cases below drive.
  if [ "$(readlink -f script/gh-issue.sh 2>/dev/null)" = "$(readlink -f "$script")" ]; then
    ok "script/gh-issue.sh resolves to the same file as $script"
  else
    bad "script/gh-issue.sh does not resolve to $script"
  fi

  gi_sandbox_start || { bad "cannot build the gh sandbox"; return; }
  gi_sandbox_proves || return
  local tmp="$GI_SANDBOX"
  local body="$tmp/body.md" gap="$tmp/gap.md" jumbled="$tmp/jumbled.md"
  local small="$tmp/small.md" noctx="$tmp/no-context.md" noscope="$tmp/no-scope.md"
  local fenced="$tmp/fenced.md" fencedonly="$tmp/fenced-only.md"

  cat >"$body" <<'BODY'
## Context
The redirect hook is new and nothing exercises it.

## Problem
A hook that stopped firing looks exactly like a hook that allows everything.

## Proposal
Assert the verdict on stdout for a direct call and for three near misses.

## Acceptance criteria
The table fails if the hook stops denying, or starts denying a heredoc.

## Out of scope
The title rules, which the script owns.
BODY
  # Proposal is missing. It is OPTIONAL, so this is a legal body and not a
  # broken one: the convention lets a small issue collapse Proposal into Problem
  # and drop Acceptance, and the check that demanded all five refused bodies the
  # convention permits.
  grep -v '^## Proposal$' "$body" >"$gap"
  # The smallest legal body: the two required sections and the one optional
  # section a one-line bug actually needs.
  cat >"$small" <<'BODY'
## Context
The label check compared names exactly, and GitHub does not.

## Problem
`--label BUG --label enhancement` was counted as one category and filed as two.

## Out of scope
The title rules, which are checked elsewhere in the same script.
BODY
  # The two that are NOT optional, each missing in turn. A relaxed check that
  # relaxed these would accept a body with no statement of what it is about and
  # no boundary at all.
  grep -v '^## Context$' "$body" >"$noctx"
  grep -v '^## Out of scope$' "$body" >"$noscope"
  # Present but in the wrong order. Order is the half a "does it contain the
  # heading" check would miss, and a body whose acceptance criteria come before
  # the problem is not a body anyone can read.
  cat >"$jumbled" <<'BODY'
## Context
c

## Proposal
p

## Problem
p

## Acceptance criteria
a

## Out of scope
o
BODY
  # A LEGAL body that quotes the section list inside code fences. This is
  # ordinary usage here -- the issues this repo files are largely about the
  # issue format, so they quote it -- and a scan with no fence state read the
  # quotation as real sections and refused the body as "sections out of order".
  # One fixture, three fence forms, because each is a separate way to get it
  # wrong: a fence opened with a language tag, a four-backtick fence whose
  # content is a three-backtick one, and a tilde fence.
  cat >"$fenced" <<'BODY'
## Context
check_body scans this file for the canonical headings. The two that a body
always carries are:

```markdown
## Context
## Out of scope
```

## Problem
Read without fence state, that quotation counts as real sections. A body that
quotes a fence has to wrap it in a longer one:

````
```
## Proposal
```
````

...and a tilde fence quotes the same thing the other way round:

~~~
## Acceptance criteria
~~~

## Out of scope
The title rules, which the script owns.
BODY
  # ...and the same defect from the other side: a body whose ONLY required
  # sections are inside a fence has quoted the shape without writing it, and
  # the scan that accepted it accepted a body with no Context and no boundary.
  cat >"$fencedonly" <<'BODY'
Prose, and no sections of its own. The shape it is describing is:

~~~markdown
## Context
c

## Out of scope
o
~~~
BODY

  # --- a full valid invocation, asserted to the character --------------------
  gi_accepts \
    "gh issue create --title 'hooks: the redirect hook has no test' --body-file $body --label enhancement --label needs-triage" \
    create --title "hooks: the redirect hook has no test" \
    --body-file "$body" --label enhancement --label needs-triage

  # A two-word scope is DOCUMENTED and legal ("issue tracker: ..."). Its
  # predecessor denied it, which is the worst outcome this check has: a false
  # deny blocks real work and catches no mistake.
  gi_accepts \
    "gh issue edit 12 --title 'issue tracker: citations go stale within a session'" \
    edit 12 --title "issue tracker: citations go stale within a session"

  # --- rule 1: a bare scope prefix, one or two words -------------------------
  gi_refuses 'rule 1' create --title "feat(hooks): the type(scope) form is for commits" \
    --body-file "$body" --label enhancement
  gi_refuses 'rule 1' create --title "No scope prefix at all here" \
    --body-file "$body" --label enhancement
  gi_refuses 'rule 1' create --title "the scope prefix here is four words: still not a scope" \
    --body-file "$body" --label enhancement
  # The edit arm is judged too. A title fixed at creation that could be edited
  # back afterwards is a rule that only holds for as long as nobody edits.
  gi_refuses 'rule 1' edit 12 --title "fix(hooks): the edit arm judges titles too"

  # --- rule 3: 80 characters, counted in characters --------------------------
  local at80 at81
  at80="hooks: an issue title padded out to exactly the eighty character ceiling here"
  at80="$at80 xx"
  at81="${at80}x"
  [ "${#at80}" = 80 ] || bad "the 80-character fixture is ${#at80} characters"
  [ "${#at81}" = 81 ] || bad "the 81-character fixture is ${#at81} characters"
  # The boundary from both sides: a fixture that drifts to 79/80 turns the only
  # length case into a second allow case, and nothing would report that.
  gi_accepts "gh issue edit 12 --title '$at80'" edit 12 --title "$at80"
  gi_refuses '81 characters' edit 12 --title "$at81"

  # 80 characters, 152 bytes. The rule counts characters, but bash's ${#s}
  # counts bytes outside a UTF-8 locale -- and this script inherits whatever
  # environment started the agent, which in a container or a CI runner is
  # routinely the POSIX default with no LANG at all. The ASCII fixtures above
  # pass either way, so this one is also run with the locale cleared.
  local multibyte
  multibyte="$(python3 -c 'print("hooks: " + "\u00e9" * 72 + "x")')"
  [ "$(python3 -c 'import sys;print(len(sys.argv[1]))' "$multibyte")" = 80 ] \
    || bad "the multibyte fixture is not 80 characters"
  gi_accepts "gh issue edit 12 --title '$multibyte'" edit 12 --title "$multibyte"
  # env -u clears the locale but keeps everything gi_env exported, so the stub
  # is still the only gh this run can find and the credentials are still the
  # invalid ones.
  : >"$GI_LOG"
  if (
       gi_env "$GI_CASE_PATH"
       exec env -u LANG -u LANGUAGE -u LC_ALL -u LC_CTYPE \
         "$script" edit 12 --title "$multibyte"
     ) >"$GI_STDOUT" 2>"$GI_STDERR"
  then
    if [ "$(cat "$GI_LOG")" = "gh issue edit 12 --title '$multibyte'" ]; then
      ok "an 80-character multibyte title passes with no locale set at all"
    else
      bad "no locale set: gh was called as $(cat "$GI_LOG")"
    fi
  else
    bad "an 80-character multibyte title was refused with no locale set: $(head -2 "$GI_STDERR" | tr '\n' ' ')"
  fi

  # --- rule 4: a heuristic, so it warns and never blocks ---------------------
  gi_accepts \
    "gh issue create --title 'hooks: should we split the redirect out' --body-file $body --label documentation" \
    create --title "hooks: should we split the redirect out" \
    --body-file "$body" --label documentation
  # ...and it has to actually say so. A warning nobody prints is a rule nobody
  # learns, and this is the one rule that cannot enforce itself.
  case "$GI_ERR" in
    *"rule 4"*) ok "rule 4 warns on stderr and still prints the gh command" ;;
    *)          bad "rule 4 produced no warning for an undecided title" ;;
  esac

  # --- the body shape --------------------------------------------------------
  # Two required sections, three optional ones, and an order over whichever are
  # present. gh-artifact-format section 2: "Small issues (one-line bug, trivial
  # doc tweak) may collapse Proposal into Problem and drop Acceptance. Context
  # and Out of scope stay." Demanding all five refused a body the convention
  # permits -- a false deny, which is the worst outcome this script has, and the
  # one an author cannot work around except by writing sections they do not mean.
  gi_accepts \
    "gh issue create --title 'hooks: a small issue collapses its body' --body-file $small --label bug" \
    create --title "hooks: a small issue collapses its body" \
    --body-file "$small" --label bug
  # ...and an optional section absent from an otherwise full body is as legal as
  # the collapsed form. This is the case that used to be a refusal.
  gi_accepts \
    "gh issue create --title 'hooks: a body with no proposal section' --body-file $gap --label bug" \
    create --title "hooks: a body with no proposal section" \
    --body-file "$gap" --label bug
  # The required two stay required, checked from both ends of the body so that
  # relaxing the middle cannot quietly relax the edges.
  gi_refuses '## Context' create --title "hooks: a body that states no context" \
    --body-file "$noctx" --label bug
  gi_refuses '## Out of scope' create --title "hooks: a body that draws no boundary" \
    --body-file "$noscope" --label bug
  # And ORDER is the half that relaxing presence must not give away: whichever
  # sections are present still appear in the canonical order, and a body whose
  # proposal arrives before its problem is not one anybody can read. The refusal
  # names the heading that is out of place rather than the one expected there,
  # because with three sections optional the expected one may legally be absent.
  gi_refuses 'out of order' create --title "hooks: a body with its sections shuffled" \
    --body-file "$jumbled" --label bug
  # Fences. A heading inside one is a quotation of the convention, not a section
  # of the body, and a scan that could not tell them apart failed both ways.
  gi_accepts \
    "gh issue create --title 'hooks: a body that quotes the section list' --body-file $fenced --label bug" \
    create --title "hooks: a body that quotes the section list" \
    --body-file "$fenced" --label bug
  gi_refuses '## Context' create --title "hooks: a body that only quotes its sections" \
    --body-file "$fencedonly" --label bug

  # --- labels ----------------------------------------------------------------
  gi_refuses 'exactly one category' create --title "hooks: a new issue with no category" \
    --body-file "$body" --label needs-triage
  gi_refuses 'exactly one category' create --title "hooks: a new issue with two categories" \
    --body-file "$body" --label bug --label enhancement
  gi_refuses 'at most one state' create --title "hooks: a new issue in two states" \
    --body-file "$body" --label bug --label needs-triage --label wontfix
  # backlog is orthogonal to the state machine and must travel with any state;
  # counting it as one is how an issue becomes unlabellable.
  gi_accepts \
    "gh issue create --title 'hooks: backlog is not a state' --body-file $body --label bug --label backlog --label ready-for-agent" \
    create --title "hooks: backlog is not a state" --body-file "$body" \
    --label bug,backlog --label ready-for-agent

  # --- a label name is matched without regard to case ------------------------
  # GitHub matches label names case-insensitively, so `--label BUG` IS the
  # repo's own `bug`. Compared exactly it was a name in neither CATEGORY_LABELS
  # nor STATE_LABELS, so `--label BUG --label enhancement` counted as ONE
  # category, was accepted, and filed as two -- the combination the rules exist
  # to prevent, reached by holding down the shift key.
  gi_refuses 'exactly one category' create --title "hooks: two categories, one of them shouted" \
    --body-file "$body" --label BUG --label enhancement
  gi_refuses 'at most one state' create --title "hooks: two states, one of them shouted" \
    --body-file "$body" --label bug --label Needs-Triage --label WONTFIX
  # The other direction is the false refusal: the category IS there, in capitals,
  # and the issue was turned away for not carrying one.
  gi_accepts \
    "gh issue create --title 'hooks: a shouted category is still a category' --body-file $body --label BUG" \
    create --title "hooks: a shouted category is still a category" \
    --body-file "$body" --label BUG
  # One label spelled two ways is one label, not a conflict -- and the name
  # reaches gh exactly as it was typed. gh resolves the case itself, and a script
  # that rewrote the author's word would be correcting something that is not
  # wrong.
  gi_accepts \
    "gh issue create --title 'hooks: one label spelled two ways' --body-file $body --label bug --label BUG" \
    create --title "hooks: one label spelled two ways" --body-file "$body" \
    --label bug --label BUG

  # --- the body always reaches gh as a file ----------------------------------
  # An inline --body is written out and passed as --body-file. A body is long,
  # carries newlines and backticks, and every one of those is a way for it to be
  # mangled on a second trip through a shell.
  # Asserted on the argv the stub captured, not on the dry-run line: what is in
  # question is what gh was handed, and the temporary path is only knowable from
  # the call itself.
  gi create --title "hooks: an inline body still goes to a file" \
    --body "$(cat "$body")" --label bug
  case "$GI_CALLS" in
    *" --body-file /"*) ok "an inline --body is passed to gh as --body-file" ;;
    *)                  bad "an inline --body did not become a --body-file: $GI_CALLS" ;;
  esac
  case "$GI_CALLS" in
    *" --body "*) bad "the body was left inline on the gh command line" ;;
    *)            ok "no body text is left on the gh command line" ;;
  esac

  # --- gh's shorthands carry their value ATTACHED ----------------------------
  # gh is a pflag program: `-lbug` and `-l=bug` are as ordinary as `-l bug`, and
  # a person reaching for a shorthand types the attached form. None of them
  # matched the case that judges the flag, so each one reached gh in passthrough
  # UNJUDGED -- a title never checked and label combinations the rules forbid
  # filed anyway. Two characters bypassed the whole script.
  gi_refuses 'exactly one category' create --title "hooks: a second category behind a shorthand" \
    --body-file "$body" --label bug -lenhancement
  gi_refuses 'at most one state' create --title "hooks: two states behind a shorthand" \
    --body-file "$body" --label bug -lneeds-triage -lwontfix
  gi_refuses 'rule 1' edit 12 "-tfeat(hooks): a title behind a shorthand"
  # ...and an attached value that is legal is normalised to the long form, so
  # the command that reaches gh reads the same however it was typed.
  gi_accepts \
    "gh issue create --title 'hooks: attached shorthands are normalised' --body-file $body --label bug --label needs-triage" \
    create "-thooks: attached shorthands are normalised" "-F$body" -lbug -l=needs-triage

  # --- ...and pflag BUNDLES them, which is attached one step further ---------
  # `-wl bug` and `-wlbug` are `--web --label bug`. The splitter required the
  # judged letter to sit immediately after the dash, so a cluster went to
  # passthrough whole and everything inside it was unjudged -- the same bypass
  # as the attached form above, reached by typing one more shorthand first.
  gi_refuses 'exactly one category' create --title "hooks: a second category inside a cluster" \
    --body-file "$body" --label bug -wlenhancement
  gi_refuses 'exactly one category' create --title "hooks: a cluster whose value is detached" \
    --body-file "$body" --label bug -wl enhancement
  gi_refuses 'rule 1' edit 12 -et "feat(hooks): a title inside a cluster"
  # A legal cluster is SPLIT, not swallowed: the leading shorthands still reach
  # gh and the judged one is normalised to its long form.
  gi_accepts \
    "gh issue create --title 'hooks: a cluster is split, not swallowed' --body-file $body --label bug -w" \
    create --title "hooks: a cluster is split, not swallowed" --body-file "$body" -wlbug
  # And a shorthand this cannot split correctly is left exactly as typed. `-a`
  # takes a value, so `-abug` is an assignee called `bug`; splitting on the `b`
  # inside somebody else's value would invent a body out of it.
  gi_accepts \
    "gh issue create --title 'hooks: an assignee is not a body' --body-file $body --label bug -abug" \
    create --title "hooks: an assignee is not a body" --body-file "$body" \
    --label bug -abug

  # --- -b, gh's documented shorthand for --body ------------------------------
  # Absent from the case, it fell into passthrough carrying the body text, so on
  # `edit` the body check was skipped entirely AND the body was left
  # inline on the gh command line -- both of the things this script exists to do.
  gi_refuses '## Context' edit 12 -b "$(cat "$noctx")"
  gi edit 12 -b "$(cat "$body")"
  case "$GI_CALLS" in
    *" --body-file /"*) ok "-b is judged and reaches gh as --body-file" ;;
    *)                  bad "-b did not become a --body-file: $GI_CALLS" ;;
  esac
  case "$GI_CALLS" in
    *" -b "*|*" --body "*) bad "-b left the body text on the gh command line" ;;
    *)                     ok "-b leaves no body text on the gh command line" ;;
  esac
  # ...on EVERY path it can arrive by. Inside a cluster it was unrecognised, so
  # `-wb TEXT` skipped the body check AND left the text inline on the gh command
  # line -- both of the things this script exists to do, at once.
  gi_refuses '## Context' edit 12 -wb "$(cat "$noctx")"
  gi edit 12 -wb "$(cat "$body")"
  case "$GI_CALLS" in
    *" --body-file /"*) ok "-b inside a cluster is judged and reaches gh as --body-file" ;;
    *)                  bad "-b inside a cluster did not become a --body-file: $GI_CALLS" ;;
  esac
  case "$GI_CALLS" in
    *" -wb "*|*" -b "*|*" --body "*)
      bad "-b inside a cluster left the body text on the gh command line: $GI_CALLS" ;;
    *) ok "-b inside a cluster leaves no body text on the gh command line" ;;
  esac

  # --- a label given twice is one label --------------------------------------
  # gh de-duplicates them and the issue ends up carrying exactly one, so
  # "two category labels: bug bug" named a conflict that did not exist and left
  # the author nothing to change.
  gi_accepts \
    "gh issue create --title 'hooks: the same label given twice' --body-file $body --label bug --label bug" \
    create --title "hooks: the same label given twice" --body-file "$body" \
    --label bug --label bug

  # --- a title is ONE line ---------------------------------------------------
  # The scope check was anchored only at the start of the string, so a title
  # whose first line was well formed passed however many lines came after it.
  gi_refuses 'single line' edit 12 \
    --title "$(printf 'hooks: a fine first line\nfeat(x): and an unread second')"

  # --- a directory is readable, and is not a body ----------------------------
  # -r passes a directory, and the read loop then died on the redirect: a bash
  # traceback ("Is a directory", then an unbound variable) where a usage error
  # belongs.
  gi_refuses 'is a directory' create --title "hooks: a directory as a body file" \
    --body-file "$tmp" --label bug
  case "$GI_ERR" in
    *"unbound variable"*|*"read error"*)
      bad "a directory body file still produces a bash error: $(printf '%s' "$GI_ERR" | head -1)" ;;
    *) ok "a directory body file is a usage error, not a bash traceback" ;;
  esac

  # --- rule 3 with neither python3 nor jq ------------------------------------
  # The fallback used to be bash's own ${#s}, which counts BYTES outside a UTF-8
  # locale: a legal 79-character title made of two-byte characters was refused
  # as "150 characters". A refusal of something the document permits is the
  # worst outcome this script has, and it appears only where the tools are
  # missing -- which is the environment nobody tests in.
  local short
  short="$(python3 -c 'print("hooks: " + "\u00e9" * 71 + "x")')"
  [ "$(python3 -c 'import sys;print(len(sys.argv[1]))' "$short")" = 79 ] \
    || bad "the 79-character fallback fixture is not 79 characters"
  : >"$GI_LOG"
  # Assert the emptiness rather than assume it: if python3 were still reachable
  # here the case would pass without ever entering the fallback, and this would
  # quietly become a duplicate of the case above.
  if PATH="$GI_BARE_PATH" command -v python3 >/dev/null 2>&1 \
     || PATH="$GI_BARE_PATH" command -v jq >/dev/null 2>&1; then
    bad "the bare PATH still has python3 or jq; the length fallback is untested"
  fi
  # ...and it is still a sandbox: the stub answers, and the tripwire is behind
  # it. A narrower PATH must not be a way out of the arrangement.
  #
  # This is a guard, so it GUARDS: the case below is the else-arm of it and does
  # not run when it fails. It used to announce "not running the fallback case"
  # and then run it on the next line -- an unproven sandbox reported as one that
  # had been refused, which is the same shape as the accident that filed three
  # real issues from this suite.
  #
  # "$BASH" is spelled out because the script's `#!/usr/bin/env bash` would
  # otherwise resolve through the bare PATH, and this must run the script rather
  # than test what the sandbox's own bash symlink happens to be.
  if [ "$(PATH="$GI_BARE_PATH" command -v gh)" != "$GI_BARE/gh" ]; then
    bad "the bare PATH does not resolve gh to the stub; not running the fallback case"
  elif (
       unset LANG LANGUAGE LC_ALL LC_CTYPE
       gi_env "$GI_BARE_PATH"
       exec "$BASH" "$script" edit 12 --title "$short"
     ) >"$GI_STDOUT" 2>"$GI_STDERR"
  then
    if [ "$(cat "$GI_LOG")" = "gh issue edit 12 --title '$short'" ]; then
      ok "a 79-character multibyte title passes with no python3, no jq, no locale"
    else
      bad "no python3 or jq: gh was called as $(cat "$GI_LOG")"
    fi
  else
    bad "a 79-character multibyte title was refused with no python3 or jq: $(head -2 "$GI_STDERR" | tr '\n' ' ')"
  fi

  # --- a comma-separated label list, written with the space people write ----
  # gh's label flags are string slices, so `--label "bug, enhancement"` is
  # ordinary usage and not an evasion. The split was here; the TRIM was not, so
  # the second name arrived as " enhancement" -- a string in neither
  # CATEGORY_LABELS nor STATE_LABELS -- and both label rules went blind at once.
  gi_refuses 'exactly one category' create --title "hooks: two categories in one spaced list" \
    --body-file "$body" --label "bug, enhancement"
  gi_refuses 'at most one state' create --title "hooks: two states in one spaced list" \
    --body-file "$body" --label bug --label "needs-triage, wontfix"
  # The other direction, which is the false refusal: the category IS there,
  # behind the space, and the issue was turned away for not carrying one.
  gi_accepts \
    "gh issue create --title 'hooks: a spaced list is trimmed, not refused' --body-file $body --label needs-triage --label bug" \
    create --title "hooks: a spaced list is trimmed, not refused" \
    --body-file "$body" --label "needs-triage, bug"
  # And the TRIMMED name is what reaches gh. A label called " enhancement"
  # exists in no repo, so forwarding the untrimmed word would only trade a rule
  # this script failed to apply for an error from gh.
  gi_accepts "gh issue edit 12 --add-label bug --add-label backlog" \
    edit 12 --add-label "bug ,  backlog "

  # --- an issue addressed by URL --------------------------------------------
  # gh takes a number or a URL. The redirect hook denies `gh issue edit <url>`
  # on its shape like every other direct call, so while this took only a number
  # there was no way through EITHER half for a form gh itself accepts: the hook
  # sent the author to the script and the script turned them away.
  gi_accepts \
    "gh issue edit https://github.com/o/r/issues/12 --title 'hooks: an issue addressed by url'" \
    edit https://github.com/o/r/issues/12 --title "hooks: an issue addressed by url"
  # The URL is an address, not an exemption: the rules still apply behind it.
  gi_refuses 'rule 1' edit https://github.com/o/r/issues/12 \
    --title "feat(hooks): a url does not exempt the title"
  gi_refuses 'number or its URL' edit not-a-target --title "hooks: neither a number nor a url"

  # --- `--` is NOT an end-of-options marker here -----------------------------
  # It is collected like any other unrecognised word, the arguments after it are
  # still read by the script, and it is re-emitted after the rewritten flags --
  # so it does not even keep the arguments it was written in front of. Pinned
  # here because the comment in the source used to claim the opposite, and a
  # caller who believed it was handed a silently different command.
  gi_accepts \
    "gh issue edit 12 --title 'hooks: the double dash is just another word' --add-label bug --" \
    edit 12 -- --add-label bug --title "hooks: the double dash is just another word"

  # --- usage errors are refusals too, not defaults ---------------------------
  gi_refuses 'create needs --title' create --body-file "$body" --label bug
  gi_refuses 'create needs a body' create --title "hooks: no body at all" --label bug

  # --- the suite's environment is built, not inherited -----------------------
  # The real arm used to inherit GH_ISSUE_DRY_RUN, so a developer who had it
  # exported in their own shell watched twenty accept cases fail against an
  # empty stub log -- a suite whose result depended on a variable belonging to
  # the code under test. Exported here deliberately, and it must change nothing.
  export GH_ISSUE_DRY_RUN=1
  gi edit 12 --title "hooks: an exported dry-run flag reaches no case"
  unset GH_ISSUE_DRY_RUN
  if [ "$GI_CALLS" = "gh issue edit 12 --title 'hooks: an exported dry-run flag reaches no case'" ]; then
    ok "an exported GH_ISSUE_DRY_RUN does not reach a case"
  else
    bad "an exported GH_ISSUE_DRY_RUN reached the script; gh was called as: $GI_CALLS"
  fi

  # --- layer 3, end to end and then not at all -------------------------------
  # Every case above ran with a credential that could not authenticate against
  # anything, so a call that somehow escaped both the stub and the tripwire
  # would have been answered with a 401 rather than by mutating an issue. The
  # stub recorded what it was handed, which is the value the real gh would have
  # used -- checked here rather than read back off the function that exports it.
  local creds bad_creds
  creds="$(LC_ALL=C sort -u "$GI_ENV_LOG")"
  bad_creds="$(printf '%s\n' "$creds" | grep -v -x -F "$GI_FAKE_TOKEN" || true)"
  if [ -z "$creds" ]; then
    bad "no case reached the stub, so the credential layer went unchecked"
  elif [ -n "$bad_creds" ]; then
    bad "a case ran with a credential that is not the test value: $bad_creds"
  else
    ok "every gh call carried the invalid test credential and no other"
  fi
  # ...and it stops at the subshell. gi_env exports inside the subshell that
  # starts the script, so ci.sh's own environment -- and the shell that ran
  # ci.sh -- never sees it.
  if [ "${GH_TOKEN-<unset>}" = "$GI_FAKE_TOKEN" ]; then
    bad "the invalid test credential leaked into ci.sh's own environment"
  else
    ok "the invalid test credential does not leak out of the case subshell"
  fi

  # --- the count of real gh invocations, before anything is torn down --------
  # First, that the assertion is capable of failing. An empty tripwire log means
  # "nothing got past the stub" only when the log is actually there to read; a
  # missing one used to be normalised to zero and reported as a clean run, so
  # the safety assertion passed hardest in the states it exists to catch. Point
  # it at a log that is not there and require it to say so. Run in a subshell,
  # so the fake teardown reaches neither the real log nor this check's tally.
  local gone
  gone="$(
    GI_REAL_LOG="$GI_SANDBOX/no-such-tripwire-log"
    rm -f -- "$GI_REAL_LOG"
    gi_no_real_gh 2>&1
    printf 'status=%s\n' "$?"
  )"
  case "$gone" in
    *"status=0"*) bad "gi_no_real_gh passed with no tripwire log to read" ;;
    *FAIL*)       ok "gi_no_real_gh fails when the tripwire log cannot be read" ;;
    *)            bad "gi_no_real_gh said nothing about a missing tripwire log: $gone" ;;
  esac
  # ...and then the count itself, on a log that is there.
  gi_no_real_gh

  # The sandbox is torn down by the EXIT trap, so this holds even when the check
  # returns early above.
  gi_sandbox_cleanup

  # --- and the teardown disarms it ------------------------------------------
  # Clearing GI_SANDBOX alone left GI_BIN pointing into a directory that had
  # just been removed. PATH="$GI_BIN:$PATH" then skips the missing directory and
  # resolves gh to /usr/bin/gh, so the next thing to call gi_invoke would have
  # run against github.com for real -- the precise shape of the failure that
  # filed three issues here, left armed for whatever came next.
  if gi_sandbox_is_live; then
    bad "the gh sandbox still reports itself live after teardown"
  elif [ -n "$GI_BIN$GI_BARE$GI_TRAP$GI_CASE_PATH$GI_BARE_PATH$GI_LOG$GI_ENV_LOG" ]; then
    bad "teardown left a sandbox path set: GI_BIN=[$GI_BIN] GI_TRAP=[$GI_TRAP] GI_CASE_PATH=[$GI_CASE_PATH]"
  else
    ok "teardown clears every sandbox path, so a later run cannot fall through to a real gh"
  fi
}

check_redirect_hook() {
  head_ "the direct-call redirect hook"
  # Deliberately small. This hook does one thing -- notice a direct
  # `gh issue create|new|edit` and name script/gh-issue.sh -- and it never reads
  # or judges a title, so there is nothing here about the rules.
  #
  # The verdict of a PreToolUse hook lives in its stdout JSON; it exits 0 to
  # deny and 0 to stay silent. Asserting on the exit status would therefore pass
  # a hook that has stopped firing entirely, which is how a sibling harness ran
  # for weeks with a hook that allowed every command.
  #
  # The allow cases are the ones that matter here. Matching is anchored at the
  # start of the command string precisely so that a heredoc body, a quoted
  # example or a `gh pr` never trips it: a missed direct call costs a nudge,
  # while a false deny blocks work the author is entitled to do.
  #
  # Driven through .agents/hooks/, so a broken symlink into dist/ fails here.
  local hook=.agents/hooks/redirect_gh_issue.sh
  if [ ! -x "$hook" ]; then
    bad "$hook is missing or not executable"
    return
  fi

  local heredoc
  heredoc=$'cat <<EOF >/tmp/body.md\ngh issue create --title "feat(x): y"\nEOF'

  local -a cases=(
    deny  'gh issue create --title "hooks: a direct call is redirected"'
    deny  'gh issue edit 12 --title "hooks: the edit arm too"'
    # `new` is gh's own alias for `create` (gh 2.98.0), a form people type.
    deny  'gh issue new --title "hooks: and the new alias"'
    # An assignment in front of a command is ordinary and must not hide it.
    deny  'GH_HOST=github.com gh issue create --title "hooks: with an assignment"'
    # A FLAG IN FRONT OF THE SUBCOMMAND MUST NOT HIDE IT EITHER. cobra strips
    # flags before it resolves the subcommand, so every one of these is a
    # working create -- and `-R`, the form automation uses to write to another
    # repo, is the call least likely to be read by a human.
    deny  'gh -R owner/repo issue create --title "hooks: a flag before the subcommand"'
    deny  'gh --repo owner/repo issue create --title "hooks: the long form too"'
    # The value may be ATTACHED, in which case the next word is NOT its value.
    deny  'gh -Rowner/repo issue create --title "hooks: pflag attaches it"'
    deny  'gh --repo=owner/repo issue create --title "hooks: and after an equals"'
    deny  'gh -R owner/repo issue edit 12 --title "hooks: the edit arm behind a flag"'
    # `--` ends cobra's search for a subcommand: `gh -- issue create` answers
    # `unknown command "issue"` and creates nothing, so denying it would refuse
    # a command that does not exist.
    allow 'gh -- issue create --title "hooks: no subcommand at all"'
    # The whole reason this replaced a title-parsing hook: the body of a heredoc
    # is text, not a command, and the old hook read an example title out of one
    # and denied the repo's own documented recipe.
    allow "$heredoc"
    # gh pr is exempt on purpose: type(scope): is still the convention for
    # commit messages and PR titles, and nothing about a PR goes through the
    # script.
    allow 'gh pr create --title "feat(hooks): PR titles keep the type prefix"'
    allow 'git commit -m "hooks: redirect gh issue create to the script"'
    # The script itself must not be redirected into itself -- at the delivered
    # path the hook names, and at this repo's own alias for it.
    allow '.agents/scripts/gh-issue.sh create --title "hooks: the script is the way in"'
    allow 'script/gh-issue.sh create --title "hooks: the repo alias too"'
    # Only create/new/edit are redirected; the read-only verbs are the ones an
    # agent uses constantly.
    allow 'gh issue list --state open'
    # A HELP LOOKUP CREATES AND EDITS NOTHING. cobra prints the flag list and
    # exits before the command body runs, so denying these blocked a harmless
    # command -- and one an author reaches for precisely because the script's
    # own --help does not list gh's flags.
    allow 'gh issue create --help'
    allow 'gh issue edit --help'
    allow 'gh issue new --help'
    allow 'gh issue create -h'
    # `edit` takes a target first, and the lookup is still a lookup behind it.
    allow 'gh issue edit 12 --help'
    # The exemption has to survive the flag-skipping, or the fix above would
    # have turned a harmless lookup into a deny.
    allow 'gh -R owner/repo issue create --help'
    allow 'gh --repo=owner/repo issue create --help'
    allow 'gh -R owner/repo issue edit 12 --help'
    allow 'gh issue edit https://github.com/o/r/issues/12 --help'
    # A help flag in front of the rest still wins: cobra never runs the body.
    allow 'gh issue create --help --title "hooks: never filed"'
    # ...and the exemption is NARROW. `--help` as the VALUE of --title files an
    # issue titled "--help", so a rule of "the word appears somewhere" would
    # wave a real create through. It has to be the first word after the
    # subcommand, or the first after a single bare target, where there is no
    # preceding flag it could belong to.
    deny 'gh issue create --title --help'
    deny 'gh issue create --title "hooks: --help inside a title"'
    deny 'gh issue edit 12 --add-label bug --help'
    # A word that merely starts with the flag is not the flag.
    deny 'gh issue create --helpful --title "hooks: not a help lookup"'
    # A URL-addressed edit is still a direct call, and the script now accepts
    # the URL, so the redirect finally has somewhere to send it.
    deny 'gh issue edit https://github.com/o/r/issues/12 --title "hooks: by url"'
  )

  # The payload goes in on a here-string rather than through a pipe: a hook that
  # decides before reading stdin is legitimate, and piping into one turns that
  # into a BrokenPipeError from the payload builder that buries the real result.
  local i n expect cmd got
  n=${#cases[@]}
  for ((i = 0; i < n; i += 2)); do
    expect="${cases[i]}"; cmd="${cases[i + 1]}"
    got="$("$hook" <<<"$(hook_payload "$cmd")" | hook_verdict)"
    if [ "$got" = "$expect" ]; then
      ok "$expect  ${cmd//$'\n'/ }"
    else
      bad "expected $expect, got $got: ${cmd//$'\n'/ }"
    fi
  done

  # A deny that does not name the way forward is just an obstacle.
  local msg
  msg="$("$hook" <<<"$(hook_payload 'gh issue create --title "hooks: x"')")"
  case "$msg" in
    *".agents/scripts/gh-issue.sh create --title"*)
      ok "the deny shows the equivalent script invocation" ;;
    *) bad "the deny does not show the .agents/scripts/gh-issue.sh invocation" ;;
  esac
}

check_hook_wiring() {
  head_ "hooks are wired into every agent's config"
  # A PreToolUse hook that no config file names is a file that never runs, and
  # from the outside that is indistinguishable from a hook that stays silent
  # about everything. Nothing else here notices: check_redirect_hook runs the
  # script by path, so it passes whether or not an agent is configured to call
  # it; check_json only parses the config files; and check_wiring drives
  # init.sh, which treats both policy files as copy-once and so cannot report
  # that one has drifted.
  #
  # The dist/ copies are checked too, because those are what a consumer's fresh
  # install gets -- a hook that ships wired to nothing redirects nobody.
  #
  # Read as JSON rather than grepped, so an entry that has been moved somewhere
  # inert (the wrong matcher, the wrong event) fails here as well as a missing
  # one.
  #
  # CODEX IS CHECKED TOO, AND USED NOT TO BE. This repo asserted for months that
  # Codex had no hook mechanism at all. That was measured, and it expired:
  # codex-cli 0.153.2 reads project hooks from <repo>/.codex/hooks.json, and a
  # hook wired there fires (demonstrated 2026-09-09 -- SessionStart and
  # PreToolUse both ran, with a Claude-Code-shaped JSON payload on stdin).
  # Its path rule is its own, which is why this arm is not a copy of either of
  # the others: Codex runs the command through a shell from the SESSION's
  # working directory, not the repo root, and sets no project-directory variable
  # -- so a bare relative path is wired and still never resolves once the agent
  # is one directory down. The command has to find the root itself.
  # Named, not globbed from dist/agents/hooks: a hook is listed here when it is
  # meant to fire for every agent, and the list is the statement of that. A new
  # hook that nothing wires is added here in the same change that ships it.
  local -a wired=(redirect_gh_issue.sh)
  local name f
  for name in "${wired[@]}"; do
    for f in .claude/settings.json dist/claude/settings.json; do
      if python3 - "$f" "$name" <<'WIRED'
import json, sys
path, name = sys.argv[1], sys.argv[2]
try:
    conf = json.load(open(path))
except Exception:
    raise SystemExit(1)
for entry in (conf.get("hooks") or {}).get("PreToolUse") or []:
    # Claude Code matches on the tool name; a hook on any other matcher is
    # wired in the file and still never fires for a Bash command.
    if entry.get("matcher") != "Bash":
        continue
    for hook in entry.get("hooks") or []:
        if hook.get("type") == "command" and name in (hook.get("command") or ""):
            raise SystemExit(0)
raise SystemExit(1)
WIRED
      then
        ok "$f runs $name (PreToolUse, matcher Bash)"
      else
        bad "$f does not run $name under PreToolUse with matcher Bash"
      fi
    done
    for f in .agents/hooks.json dist/agents/hooks.json; do
      if python3 - "$f" "$name" <<'WIRED'
import json, sys
path, name = sys.argv[1], sys.argv[2]
try:
    conf = json.load(open(path))
except Exception:
    raise SystemExit(1)
for group in conf.values():
    if not isinstance(group, dict):
        continue
    for entry in group.get("PreToolUse") or []:
        if entry.get("matcher") != "*":
            continue
        for hook in entry.get("hooks") or []:
            command = hook.get("command") or ""
            # agy resolves a hook command relative to .agents/, so the path has
            # to be the ./hooks/ form: an absolute or $CLAUDE_PROJECT_DIR path
            # parses as JSON and then fails to execute.
            if (hook.get("type") == "command" and name in command
                    and command.startswith("./hooks/")):
                raise SystemExit(0)
raise SystemExit(1)
WIRED
      then
        ok "$f runs $name (PreToolUse, matcher *, ./hooks/ path)"
      else
        bad "$f does not run $name under PreToolUse with matcher * and a ./hooks/ path"
      fi
    done
    for f in .codex/hooks.json dist/codex/hooks.json; do
      if python3 - "$f" "$name" <<'WIRED'
import json, sys
path, name = sys.argv[1], sys.argv[2]
try:
    conf = json.load(open(path))
except Exception:
    raise SystemExit(1)
for entry in (conf.get("hooks") or {}).get("PreToolUse") or []:
    # "*" is the matcher a Codex PreToolUse hook was demonstrated to fire on.
    if entry.get("matcher") != "*":
        continue
    for hook in entry.get("hooks") or []:
        command = hook.get("command") or ""
        # The command runs in a shell, from the session's directory rather than
        # the repo root, with no project-directory variable set. So it has to
        # resolve the root itself; a path that starts with ./ or .agents/ is
        # wired and inert the moment the agent is one directory down.
        if (hook.get("type") == "command" and name in command
                and "git rev-parse --show-toplevel" in command):
            raise SystemExit(0)
raise SystemExit(1)
WIRED
      then
        ok "$f runs $name (PreToolUse, matcher *, self-locating path)"
      else
        bad "$f does not run $name under PreToolUse with matcher * and a \$(git rev-parse --show-toplevel) path"
      fi
    done
  done
}

# A throwaway install, removed however the check ends. Same reasoning as the gh
# sandbox: an early return or a bad() that abandons the rest must not leave a
# tree behind.
SHIP_TMP=""
ship_cleanup() {
  [ -n "$SHIP_TMP" ] && rm -rf -- "$SHIP_TMP"
  SHIP_TMP=""
  return 0
}

# One invocation of a consumer's DELIVERED gh-issue.sh, from inside that
# consumer, in the gh sandbox, with this repo's project directory cleared --
# the consumer's project is the consumer. stderr and stdout together, because
# what is being collected is everything the script says.
ship_say() {                      # ship_say <consumer-root> <args...>
  local at="$1"; shift
  ( cd "$at" || exit 1
    gi_env "$GI_CASE_PATH"
    exec .agents/scripts/gh-issue.sh "$@"
  ) 2>&1
}

check_ship() {
  head_ "a fresh install carries what the shipped hook names"
  # The redirect hook is SHIPPED (dist/agents/hooks) and both dist config files
  # wire it, so its message is read in repos that are not this one. While the
  # script it named lived in script/ -- a directory dist/ does not ship -- a
  # fresh install got a hook telling its author to run a file the install had
  # never delivered, and nothing in this repo noticed, because here that path
  # happened to exist.
  #
  # So this installs the harness the way a consumer does, into a throwaway git
  # repo, and then asks the HOOK ITSELF which paths it names rather than
  # repeating a list here. That is what keeps the check honest: point the
  # message at something new and this demands the new thing be shipped too.
  #
  # Nothing here runs the script or reaches a network: the paths are parsed out
  # of the hook's own deny message, and each one is checked for existence and
  # parsed with `bash -n`.
  command -v git >/dev/null || { bad "git is required"; return; }

  SHIP_TMP="$(mktemp -d)" || { bad "cannot create a temporary directory"; return; }
  local consumer="$SHIP_TMP/consumer" harness
  harness="$consumer/.agent_harness"
  mkdir -p "$harness" || { bad "cannot build the consumer tree"; return; }
  git -C "$consumer" init -q >/dev/null 2>&1 \
    || { bad "cannot git init the consumer tree"; return; }
  # Exactly what a `git subtree add` of this repo would place there.
  cp -a .version dist init.sh upgrade.sh "$harness/" \
    || { bad "cannot copy the harness payload"; return; }

  local out
  if ! out="$("$harness/init.sh" 2>&1)"; then
    bad "init.sh failed in a fresh consumer repo:"
    printf '%s\n' "$out" | sed 's/^/       /'
    return
  fi
  ok "init.sh installs into a fresh consumer repo"

  # THE CODEX POLICY FILE, DELIVERED AND THEN ACTUALLY RUN.
  # Two failures are possible here and neither shows up anywhere else. The file
  # can simply not be delivered -- init.sh's own UNWIRED report says nothing
  # about a policy file that is absent, so dropping the copy_once line would be
  # silent. And the command inside it can be wired correctly and still not
  # resolve: Codex runs it through a shell from the SESSION's directory, not the
  # repo root, so a path that works at the root is inert one directory down.
  # That is why this takes the command string out of the delivered file and runs
  # it the way a shell would, from a subdirectory, and demands the deny.
  local codex_conf="$consumer/.codex/hooks.json" ccmd cverdict
  if [ ! -e "$codex_conf" ]; then
    bad "a fresh install does not carry .codex/hooks.json, so Codex runs no hook"
  elif ! ccmd="$(python3 - "$codex_conf" <<'CODEXCMD'
import json, sys
conf = json.load(open(sys.argv[1]))
for entry in (conf.get("hooks") or {}).get("PreToolUse") or []:
    for hook in entry.get("hooks") or []:
        if hook.get("type") == "command" and (hook.get("command") or ""):
            print(hook["command"])
            raise SystemExit(0)
raise SystemExit(1)
CODEXCMD
  )"; then
    bad ".codex/hooks.json is delivered but names no PreToolUse command"
  else
    mkdir -p "$consumer/one/two"
    cverdict="$( cd "$consumer/one/two" && env -u CLAUDE_PROJECT_DIR sh -c "$ccmd" \
      <<<"$(hook_payload 'gh issue create --title "hooks: x"')" | hook_verdict )"
    if [ "$cverdict" = deny ]; then
      ok "the delivered .codex/hooks.json command resolves and denies from a subdirectory"
    else
      bad "the delivered .codex/hooks.json command gave '$cverdict' from a subdirectory: $ccmd"
    fi
  fi

  # The deny message, from the DELIVERED copy, read IN THE CONSUMER TREE. Both
  # halves matter. Running this repo's copy from this repo's working directory
  # asks what the message says here, and what it says here is not what a
  # consumer reads: the message names a document only where that document
  # exists, so a check standing in this repo would approve a citation the
  # consumer cannot follow.
  local hook="$consumer/.agents/hooks/redirect_gh_issue.sh" reason
  reason="$( cd "$consumer" && env -u CLAUDE_PROJECT_DIR "$hook" \
    <<<"$(hook_payload 'gh issue create --title "hooks: x"')" )" || reason=""
  reason="$(printf '%s' "$reason" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(0)
out = json.loads(raw)
sys.stdout.write((out.get("hookSpecificOutput") or {}).get("permissionDecisionReason") or "")')"
  if [ -z "$reason" ]; then
    bad "the shipped hook produced no deny message to check"
    return
  fi

  # THE SHIPPED SCRIPT'S MESSAGES TOO, and for the same reason. The hook is a
  # nudge; the script is where every rule is stated, and each refusal used to
  # end "see doc/agents/issue-tracker.md" -- a file dist/ does not ship. A
  # consumer was handed a rule whose authority they had never been given, which
  # reads as a broken install and answers nothing. Every message is collected
  # here and held to the same test as the hook's: name nothing this install
  # lacks.
  #
  # These run inside the gh sandbox, stub first on PATH, like every other
  # invocation of this script anywhere in this suite. Nothing here should reach
  # gh -- they are refusals and a usage dump -- but "should not" is not the
  # guarantee this suite runs on.
  gi_sandbox_start || { bad "cannot build the gh sandbox for the shipped script"; return; }
  gi_sandbox_proves || return
  local cbody="$consumer/body.md" cbad="$consumer/not-a-body.md"
  printf '## Context\nc\n\n## Problem\np\n\n## Proposal\np\n\n## Acceptance criteria\na\n\n## Out of scope\no\n' >"$cbody"
  printf 'no headings at all\n' >"$cbad"
  local said=""
  said+="$(ship_say "$consumer" --help)"$'\n'
  said+="$(ship_say "$consumer" create --title "no scope prefix here" \
    --body-file body.md --label bug)"$'\n'
  said+="$(ship_say "$consumer" create --title "hooks: a title stretched well past the eighty character ceiling that the rules set" \
    --body-file body.md --label bug)"$'\n'
  said+="$(ship_say "$consumer" create --title "hooks: a body with no headings" \
    --body-file not-a-body.md --label bug)"$'\n'
  said+="$(ship_say "$consumer" create --title "hooks: two categories" \
    --body-file body.md --label "bug, enhancement")"$'\n'
  said+="$(ship_say "$consumer" create --title "hooks: two states" \
    --body-file body.md --label bug --label "needs-triage, wontfix")"$'\n'
  said+="$(ship_say "$consumer" edit not-a-target --title "hooks: a bad target")"$'\n'
  if [ -z "$(printf '%s' "$said" | tr -d '[:space:]')" ]; then
    bad "the shipped script produced no messages to check"
    return
  fi
  gi_no_real_gh
  gi_sandbox_cleanup

  # Every repo-relative path either of them names. A path is what a reader would
  # copy, open or run: at least one slash, and an extension this repo delivers.
  # Absolute paths are excluded -- /tmp/body.md in an example is not something
  # the install is supposed to carry -- which is why this is a python matcher
  # with a lookbehind rather than a grep -oE.
  local -a named=()
  while IFS= read -r path; do
    [ -n "$path" ] && named+=("$path")
  done < <(printf '%s\n%s\n' "$reason" "$said" | python3 -c '
import re, sys
seen = []
for m in re.finditer(r"(?<![\w./-])([A-Za-z0-9_.][\w./-]*/[\w.-]+\.(?:sh|md))", sys.stdin.read()):
    if m.group(1) not in seen:
        seen.append(m.group(1))
print("\n".join(sorted(seen)))')

  if [ "${#named[@]}" = 0 ]; then
    bad "neither shipped file names a path at all; the deny has to say the way forward"
    return
  fi

  local path
  for path in "${named[@]}"; do
    if [ ! -e "$consumer/$path" ]; then
      bad "a shipped message names $path, which a fresh install does not have"
    elif [ "${path%.sh}" != "$path" ] && [ ! -x "$consumer/$path" ]; then
      bad "$path is delivered but is not executable"
    elif [ "${path%.sh}" != "$path" ] && ! bash -n "$consumer/$path" 2>/dev/null; then
      bad "$path is delivered but does not parse"
    else
      ok "$path is named by a shipped message and delivered by a fresh install"
    fi
  done

  # --- a consumer that ALREADY has .claude/settings.json ---------------------
  # The normal case when adopting the harness into an existing project. Both
  # policy files are copy_once, so init.sh keeps theirs -- correctly, it is
  # theirs -- and every hook this harness ships is wired from one of those two
  # files. The install therefore delivered a hook that can never fire, and said
  # nothing: it printed "keep .claude/settings.json (yours)" and finished green.
  #
  # init.sh still does not edit a file the consumer owns. What is checked here
  # is that it no longer does it QUIETLY. Wiring the entry for them -- a managed
  # region in a file somebody else maintains, an opt-out for a hook they removed
  # on purpose, and upgrade semantics for both -- is a change to what copy_once
  # means, and is not what this check asserts.
  local existing="$SHIP_TMP/existing" eharness
  eharness="$existing/.agent_harness"
  mkdir -p "$eharness" "$existing/.claude" || { bad "cannot build the second consumer"; return; }
  git -C "$existing" init -q >/dev/null 2>&1 \
    || { bad "cannot git init the second consumer"; return; }
  printf '{ "permissions": { "allow": ["Bash(ls:*)"] } }\n' >"$existing/.claude/settings.json"
  cp -a .version dist init.sh upgrade.sh "$eharness/" \
    || { bad "cannot copy the harness payload"; return; }
  local eout
  eout="$("$eharness/init.sh" 2>&1)" || { bad "init.sh failed against an existing settings.json"; return; }
  case "$eout" in
    *"UNWIRED"*".claude/settings.json"*"redirect_gh_issue.sh"*)
      ok "init.sh reports a kept settings.json that wires no shipped hook" ;;
    *)
      bad "init.sh kept an existing .claude/settings.json and said nothing about the unwired hook" ;;
  esac
  # And it is a report, not a rewrite: the consumer's file is untouched.
  if grep -q redirect_gh_issue.sh "$existing/.claude/settings.json"; then
    bad "init.sh edited a policy file the consumer owns"
  else
    ok "init.sh leaves the consumer's settings.json exactly as it found it"
  fi
  # A repo whose own config DOES wire the hook must stay quiet, or the report
  # is noise everybody learns to skip. The first consumer is that repo.
  case "$out" in
    *UNWIRED*) bad "init.sh reported UNWIRED for a fresh install it wired itself" ;;
    *)         ok "a fresh install, which init.sh wires itself, reports no UNWIRED hook" ;;
  esac

  # QUIET ABOUT THE WIRING IS NOT QUIET ABOUT THE GATES, and this check exists
  # because the two were confused. Codex's hook file is delivered wired and the
  # UNWIRED report is therefore correctly silent -- but on the consumer's
  # machine the hook still does not run until the project is trusted in
  # ~/.codex/config.toml and the hook has been reviewed, and under `codex exec`
  # failing either produces no hook line and no warning. An install that said
  # "copy .codex/hooks.json" and then "done" is read as "the Codex hook is
  # live", which is the same failure report_unwired was added to end for
  # .claude/settings.json. init.sh cannot clear either gate -- both live outside
  # the repo -- so what is asserted here is that it says so.
  case "$out" in
    *GATED*".codex/hooks.json"*trust_level*review*)
      ok "init.sh names both Codex trust gates when it delivers .codex/hooks.json" ;;
    *)
      bad "init.sh delivered .codex/hooks.json without naming the two trust gates" ;;
  esac

  ship_cleanup
}

# The single list of checks. "all" derives from it, and CI runs only "all",
# so adding a check here gates pull requests immediately -- there is no second
# place to keep in sync.
CHECKS=(lint actionlint json frontmatter structure wiring lock gh_issue
        redirect_hook hook_wiring ship)

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
