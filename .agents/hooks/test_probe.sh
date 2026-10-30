#!/usr/bin/env bash
# Test probe: appends a line to hook-probe.log at the repo root whenever it is
# invoked, so we can tell which agents actually execute hooks -- and which RUN
# a line belongs to.
#
# Two of the four fields come from the environment, and BOTH are optional. This
# hook fires on every Bash call in this repo during ordinary work, where neither
# is set; that path must stay silent, fast and successful, so each has a
# defined-but-useless default rather than a failure.
#
#   AGENT_NAME   which agent ran the hook. Set by an env prefix on the hook
#                command in .claude/settings.json and .agents/hooks.json, since
#                both agents execute that command through a shell. Unset ->
#                "unknown", which is what EVERY line said until those prefixes
#                existed: the log recorded that a hook had fired and never which
#                agent fired it.
#   PROBE_NONCE  which run a line belongs to. Exported by
#                script/verify-agents.sh for the one agent process it launches,
#                and inherited by the hook that process spawns. Unset -> "none".
#                The agent name alone cannot separate a verification run from a
#                concurrent session of the same agent in the same repo, and this
#                machine routinely has several.
set -u
root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
printf '%s  agent=%s  event=%s  nonce=%s\n' \
  "$(date -Is)" "${AGENT_NAME:-unknown}" "${1:-no-arg}" "${PROBE_NONCE:-none}" \
  >> "$root/hook-probe.log"
exit 0
