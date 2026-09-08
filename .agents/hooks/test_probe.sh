#!/usr/bin/env bash
# 測試探針：被呼叫就在 repo 根目錄留下一行紀錄，用來確認各 agent 有沒有真的執行 hook。
set -u
root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
printf '%s  agent=%s  event=%s\n' \
  "$(date -Is)" "${AGENT_NAME:-unknown}" "${1:-no-arg}" >> "$root/hook-probe.log"
exit 0
