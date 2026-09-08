#!/usr/bin/env bash
# Test probe: appends a line to hook-probe.log at the repo root whenever it is
# invoked, so we can tell which agents actually execute hooks.
set -u
root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
printf '%s  agent=%s  event=%s\n' \
  "$(date -Is)" "${AGENT_NAME:-unknown}" "${1:-no-arg}" >> "$root/hook-probe.log"
exit 0
